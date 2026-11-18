package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strconv"
)

const serviceVersion = "1"

// apiServer 只监听 127.0.0.1，并且：
//   - 必须带 X-Koyun-Token（令牌在只有服务和安装用户能读的文件里）
//   - Host 必须是 127.0.0.1:端口，拒绝带 Origin 的请求（防止网页通过 DNS 重绑定 / 跨站请求调用）
type apiServer struct {
	core  *coreManager
	token string
	host  string
}

func newToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

func listenLocal() (net.Listener, int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, 0, err
	}
	return l, l.Addr().(*net.TCPAddr).Port, nil
}

func (s *apiServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Host != s.host || r.Header.Get("Origin") != "" ||
		subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Koyun-Token")), []byte(s.token)) != 1 {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	switch {
	case r.Method == http.MethodGet && r.URL.Path == "/v1/status":
		writeJSON(w, http.StatusOK, s.core.status())
	case r.Method == http.MethodGet && r.URL.Path == "/v1/version":
		writeJSON(w, http.StatusOK, map[string]string{"version": serviceVersion})
	case r.Method == http.MethodGet && r.URL.Path == "/v1/logs":
		since, _ := strconv.Atoi(r.URL.Query().Get("since"))
		lines, next := s.core.logsSince(since)
		writeJSON(w, http.StatusOK, map[string]any{"lines": lines, "next": next})
	case r.Method == http.MethodPost && r.URL.Path == "/v1/start":
		body, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		st, err := s.core.start(body)
		if err != nil {
			writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"error": err.Error(), "status": st})
			return
		}
		writeJSON(w, http.StatusOK, st)
	case r.Method == http.MethodPost && r.URL.Path == "/v1/stop":
		s.core.stop()
		writeJSON(w, http.StatusOK, s.core.status())
	default:
		http.NotFound(w, r)
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// stateFile 是 App 读取的连接信息
type stateFile struct {
	Port    int    `json:"port"`
	Token   string `json:"token"`
	Version string `json:"version"`
}
