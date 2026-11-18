package main

import (
	"encoding/json"
	"testing"
)

func TestSanitizeRemovesFileWrites(t *testing.T) {
	in := `{
	 "log":{"level":"info","output":"C:\\Windows\\System32\\evil.dll"},
	 "services":[{"type":"ssm-api","cache_path":"C:\\x"}],
	 "unknown":1,
	 "experimental":{
	   "cache_file":{"enabled":true,"path":"C:\\Windows\\x.db"},
	   "clash_api":{"external_controller":"127.0.0.1:9090","secret":"s","external_ui":"C:\\Windows\\ui","external_ui_download_url":"http://x"},
	   "v2ray_api":{"listen":"127.0.0.1:1"}
	 },
	 "route":{"rule_set":[
	   {"type":"local","tag":"a","path":"C:\\Users\\u\\geoip-cn.srs"},
	   {"type":"remote","tag":"b","url":"http://x","path":"C:\\Windows\\y"}
	 ]},
	 "inbounds":[{"type":"tun"}],"outbounds":[{"type":"direct"}],"dns":{}
	}`
	out, err := sanitizeConfig([]byte(in))
	if err != nil {
		t.Fatal(err)
	}
	var c map[string]any
	if err := json.Unmarshal(out, &c); err != nil {
		t.Fatal(err)
	}
	if _, ok := c["services"]; ok {
		t.Error("services kept")
	}
	if _, ok := c["unknown"]; ok {
		t.Error("unknown top-level key kept")
	}
	if _, ok := c["log"].(map[string]any)["output"]; ok {
		t.Error("log.output kept")
	}
	exp := c["experimental"].(map[string]any)
	if _, ok := exp["v2ray_api"]; ok {
		t.Error("v2ray_api kept")
	}
	if _, ok := exp["cache_file"].(map[string]any)["path"]; ok {
		t.Error("cache_file.path kept")
	}
	api := exp["clash_api"].(map[string]any)
	if _, ok := api["external_ui"]; ok {
		t.Error("external_ui kept")
	}
	if api["secret"] != "s" || api["external_controller"] != "127.0.0.1:9090" {
		t.Error("clash api settings lost")
	}
	sets := c["route"].(map[string]any)["rule_set"].([]any)
	if sets[0].(map[string]any)["path"] == nil {
		t.Error("local rule-set path must stay (read only)")
	}
	if _, ok := sets[1].(map[string]any)["path"]; ok {
		t.Error("remote rule-set path kept")
	}
	for _, k := range []string{"inbounds", "outbounds", "dns"} {
		if _, ok := c[k]; !ok {
			t.Errorf("%s lost", k)
		}
	}
}

func TestSanitizeRejectsGarbage(t *testing.T) {
	if _, err := sanitizeConfig([]byte("not json")); err == nil {
		t.Error("expected error")
	}
}
