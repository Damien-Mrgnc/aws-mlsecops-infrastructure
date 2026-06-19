package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"regexp"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"golang.org/x/time/rate"
)

// ── Patterns de détection Prompt Injection ──────────────────────────────────

var injectionPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)ignore\s+(all\s+)?previous\s+instructions`),
	regexp.MustCompile(`(?i)you\s+are\s+now\s+`),
	regexp.MustCompile(`(?i)jailbreak`),
	regexp.MustCompile(`(?i)act\s+as\s+`),
	regexp.MustCompile(`(?i)pretend\s+(you\s+are|to\s+be)`),
	regexp.MustCompile(`(?i)disregard\s+(your|all)`),
	regexp.MustCompile(`(?i)forget\s+everything`),
}

// ── Rate limiting par clé API et par IP (en mémoire) ────────────────────────

var (
	limiters   = make(map[string]*rate.Limiter)
	limitersMu sync.Mutex

	ipLimiters   = make(map[string]*rate.Limiter)
	ipLimitersMu sync.Mutex
)

func getLimiter(apiKey string) *rate.Limiter {
	limitersMu.Lock()
	defer limitersMu.Unlock()
	if l, ok := limiters[apiKey]; ok {
		return l
	}
	// 10 requêtes/seconde, burst de 20
	l := rate.NewLimiter(rate.Limit(10), 20)
	limiters[apiKey] = l
	return l
}

func getIPLimiter(ip string) *rate.Limiter {
	ipLimitersMu.Lock()
	defer ipLimitersMu.Unlock()
	if l, ok := ipLimiters[ip]; ok {
		return l
	}
	// 30 requêtes/seconde par IP, burst de 50
	l := rate.NewLimiter(rate.Limit(30), 50)
	ipLimiters[ip] = l
	return l
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return xff
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// ── Utilitaires ──────────────────────────────────────────────────────────────

func hashAPIKey(key string) string {
	h := sha256.Sum256([]byte(key))
	return fmt.Sprintf("%x", h[:8])
}

func detectInjection(body string) bool {
	for _, p := range injectionPatterns {
		if p.MatchString(body) {
			return true
		}
	}
	return false
}

// ── Audit logging ────────────────────────────────────────────────────────────

type auditEvent struct {
	EventID    string `json:"event_id"`
	Timestamp  string `json:"timestamp"`
	APIKeyHash string `json:"api_key_hash"`
	Action     string `json:"action"`
	Reason     string `json:"reason,omitempty"`
}

func logAudit(ddb *dynamodb.Client, tableName, localMode, keyHash, action, reason string) {
	event := auditEvent{
		EventID:    fmt.Sprintf("%d", time.Now().UnixNano()),
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
		APIKeyHash: keyHash,
		Action:     action,
		Reason:     reason,
	}

	if localMode == "true" || ddb == nil {
		// Mode local : log dans stdout
		data, _ := json.Marshal(event)
		log.Printf("[AUDIT] %s", data)
		return
	}

	// Mode prod : écriture asynchrone dans DynamoDB
	go func() {
		_, err := ddb.PutItem(context.Background(), &dynamodb.PutItemInput{
			TableName: &tableName,
			Item: map[string]types.AttributeValue{
				"event_id":     &types.AttributeValueMemberS{Value: event.EventID},
				"timestamp":    &types.AttributeValueMemberS{Value: event.Timestamp},
				"api_key_hash": &types.AttributeValueMemberS{Value: event.APIKeyHash},
				"action":       &types.AttributeValueMemberS{Value: event.Action},
				"reason":       &types.AttributeValueMemberS{Value: event.Reason},
			},
		})
		if err != nil {
			log.Printf("[AUDIT ERROR] %v", err)
		}
	}()
}

// ── Main ─────────────────────────────────────────────────────────────────────

func main() {
	targetURL := getEnv("FASTAPI_URL", "http://localhost:8000")
	tableName := getEnv("DYNAMODB_TABLE", "mlsecops-audit")
	port := getEnv("PROXY_PORT", "8080")
	localMode := getEnv("LOCAL_MODE", "false")

	// Init DynamoDB (ignoré en mode local)
	var ddbClient *dynamodb.Client
	if localMode != "true" {
		cfg, err := config.LoadDefaultConfig(context.Background())
		if err != nil {
			log.Printf("[WARN] Impossible de charger la config AWS, passage en mode local: %v", err)
			localMode = "true"
		} else {
			ddbClient = dynamodb.NewFromConfig(cfg)
		}
	}

	target, err := url.Parse(targetURL)
	if err != nil {
		log.Fatalf("URL FastAPI invalide: %v", err)
	}
	proxy := httputil.NewSingleHostReverseProxy(target)

	// ── Handler principal ──────────────────────────────────────────────────
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// 0. Rate limiting par IP (avant toute auth)
		ip := clientIP(r)
		if !getIPLimiter(ip).Allow() {
			writeJSON(w, http.StatusTooManyRequests, `{"error":"ip rate limit exceeded"}`)
			return
		}

		// 1. Vérification de la clé API
		apiKey := r.Header.Get("X-API-Key")
		if apiKey == "" {
			writeJSON(w, http.StatusUnauthorized, `{"error":"missing X-API-Key header"}`)
			return
		}
		keyHash := hashAPIKey(apiKey)

		// 2. Rate limiting
		if !getLimiter(apiKey).Allow() {
			logAudit(ddbClient, tableName, localMode, keyHash, "BLOCKED", "rate_limit_exceeded")
			writeJSON(w, http.StatusTooManyRequests, `{"error":"rate limit exceeded"}`)
			return
		}

		// 3. Détection Prompt Injection sur le preview du body
		bodyPreview := r.Header.Get("X-Request-Body-Preview")
		if bodyPreview != "" && detectInjection(bodyPreview) {
			logAudit(ddbClient, tableName, localMode, keyHash, "BLOCKED", "prompt_injection_detected")
			writeJSON(w, http.StatusForbidden, `{"error":"request blocked by security policy"}`)
			return
		}

		// 4. Requête autorisée — on log et on forward
		logAudit(ddbClient, tableName, localMode, keyHash, "ALLOWED", "")
		r.Host = target.Host
		proxy.ServeHTTP(w, r)
	})

	// ── Health check ───────────────────────────────────────────────────────
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		mode := "prod"
		if localMode == "true" {
			mode = "local"
		}
		writeJSON(w, http.StatusOK, fmt.Sprintf(`{"status":"ok","service":"go-proxy","mode":"%s"}`, mode))
	})

	log.Printf("[GO-PROXY] Démarrage sur :%s → %s (mode: %s)", port, targetURL, map[string]string{"true": "local", "false": "prod"}[localMode])
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func writeJSON(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	fmt.Fprint(w, body)
}

