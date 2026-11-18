package main

import (
	"encoding/json"
	"fmt"
)

// 服务以 SYSTEM 身份运行内核，配置却来自普通用户。为了不让配置被用来以系统权限写任意文件，
// 这里只保留 Koyun 用得到的部分，并去掉所有“写文件”的路径：
//   - 顶层只允许已知字段（去掉 services 等可能写文件的功能）
//   - log.output 去掉（日志只走标准输出，由服务收集）
//   - cache_file.path 去掉（落到服务自己的数据目录）
//   - clash_api 不能下载网页面板到磁盘
//   - 远程规则集不能指定保存路径
var allowedTop = map[string]bool{
	"log": true, "dns": true, "ntp": true, "certificate": true, "endpoints": true,
	"inbounds": true, "outbounds": true, "route": true, "experimental": true,
}

func sanitizeConfig(raw []byte) ([]byte, error) {
	var cfg map[string]any
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return nil, fmt.Errorf("config is not valid JSON: %w", err)
	}
	for k := range cfg {
		if !allowedTop[k] {
			delete(cfg, k)
		}
	}
	if log, ok := cfg["log"].(map[string]any); ok {
		delete(log, "output")
	}
	if exp, ok := cfg["experimental"].(map[string]any); ok {
		for k := range exp {
			if k != "cache_file" && k != "clash_api" {
				delete(exp, k)
			}
		}
		if cf, ok := exp["cache_file"].(map[string]any); ok {
			delete(cf, "path")
		}
		if api, ok := exp["clash_api"].(map[string]any); ok {
			delete(api, "external_ui")
			delete(api, "external_ui_download_url")
			delete(api, "external_ui_download_detour")
		}
	}
	if route, ok := cfg["route"].(map[string]any); ok {
		if sets, ok := route["rule_set"].([]any); ok {
			for _, s := range sets {
				if m, ok := s.(map[string]any); ok && m["type"] == "remote" {
					delete(m, "path")
				}
			}
		}
	}
	return json.Marshal(cfg)
}
