//go:build !windows

package main

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// 需要真实内核：SINGBOX=/path/to/sing-box go test ./...
func newTestAPI(t *testing.T) (*apiServer, *httptest.Server) {
	bin := os.Getenv("SINGBOX")
	if bin == "" {
		t.Skip("SINGBOX not set")
	}
	core := &coreManager{binary: bin, dataDir: t.TempDir()}
	ts := httptest.NewServer(nil)
	api := &apiServer{core: core, token: newToken(), host: strings.TrimPrefix(ts.URL, "http://")}
	ts.Config.Handler = api
	t.Cleanup(func() { core.stop(); ts.Close() })
	return api, ts
}

func call(t *testing.T, api *apiServer, ts *httptest.Server, method, path, body string, hdr map[string]string) (int, string) {
	req, _ := http.NewRequest(method, ts.URL+path, strings.NewReader(body))
	req.Header.Set("X-Koyun-Token", api.token)
	for k, v := range hdr {
		if v == "" {
			req.Header.Del(k)
		} else {
			req.Header.Set(k, v)
		}
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return res.StatusCode, string(b)
}

func TestAuth(t *testing.T) {
	api, ts := newTestAPI(t)
	if c, _ := call(t, api, ts, "GET", "/v1/status", "", map[string]string{"X-Koyun-Token": ""}); c != 403 {
		t.Errorf("no token: %d", c)
	}
	if c, _ := call(t, api, ts, "GET", "/v1/status", "", map[string]string{"X-Koyun-Token": "wrong"}); c != 403 {
		t.Errorf("bad token: %d", c)
	}
	if c, _ := call(t, api, ts, "GET", "/v1/status", "", map[string]string{"Origin": "https://evil.example"}); c != 403 {
		t.Errorf("browser origin: %d", c)
	}
	req, _ := http.NewRequest("GET", ts.URL+"/v1/status", nil)
	req.Host = "evil.example"
	req.Header.Set("X-Koyun-Token", api.token)
	if res, err := http.DefaultClient.Do(req); err != nil || res.StatusCode != 403 {
		t.Errorf("dns rebinding host accepted")
	}
	if c, _ := call(t, api, ts, "GET", "/v1/status", "", nil); c != 200 {
		t.Errorf("good request: %d", c)
	}
}

func TestStartStopLogs(t *testing.T) {
	api, ts := newTestAPI(t)
	cfg := fmt.Sprintf(`{"log":{"level":"info","output":"%s"},
	  "inbounds":[{"type":"mixed","listen":"127.0.0.1","listen_port":18733}],
	  "outbounds":[{"type":"direct"}]}`, filepath.Join(t.TempDir(), "should-not-exist.log"))
	c, body := call(t, api, ts, "POST", "/v1/start", cfg, nil)
	if c != 200 || !strings.Contains(body, `"running":true`) {
		t.Fatalf("start: %d %s", c, body)
	}
	written, _ := os.ReadFile(filepath.Join(api.core.dataDir, "config.json"))
	if strings.Contains(string(written), "should-not-exist") {
		t.Error("log.output was not removed")
	}
	time.Sleep(300 * time.Millisecond)
	if _, body := call(t, api, ts, "GET", "/v1/logs?since=0", "", nil); !strings.Contains(body, "started") {
		t.Errorf("logs missing start line: %s", body)
	}
	if c, body := call(t, api, ts, "POST", "/v1/stop", "", nil); c != 200 || strings.Contains(body, `"running":true`) {
		t.Errorf("stop: %d %s", c, body)
	}
}

func TestStartFailureReportsError(t *testing.T) {
	api, ts := newTestAPI(t)
	// 两个入站抢同一个端口：内核立即退出，接口要返回错误原因
	cfg := `{"inbounds":[{"type":"mixed","tag":"a","listen":"127.0.0.1","listen_port":18734},
	  {"type":"mixed","tag":"b","listen":"127.0.0.1","listen_port":18734}],"outbounds":[{"type":"direct"}]}`
	c, body := call(t, api, ts, "POST", "/v1/start", cfg, nil)
	if c != 422 || !strings.Contains(body, "error") {
		t.Fatalf("expected failure: %d %s", c, body)
	}
}
