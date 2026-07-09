import SwiftUI
import WebKit

@available(iOS 26.0, *)
struct RouteWebMapPicker: UIViewRepresentable {
    let startAddress: String
    let endAddress: String
    let activeRole: RouteLocationRole
    let onCancel: () -> Void
    let onSave: (_ startAddress: String, _ endAddress: String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onSave: onSave)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "routePicker")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: URL(string: "https://localhost"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onCancel: () -> Void
        let onSave: (_ startAddress: String, _ endAddress: String) -> Void

        init(
            onCancel: @escaping () -> Void,
            onSave: @escaping (_ startAddress: String, _ endAddress: String) -> Void
        ) {
            self.onCancel = onCancel
            self.onSave = onSave
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "routePicker",
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else {
                return
            }

            if type == "cancel" {
                onCancel()
                return
            }

            if type == "save",
               let startAddress = payload["startAddress"] as? String,
               let endAddress = payload["endAddress"] as? String {
                onSave(startAddress, endAddress)
            }
        }
    }

    private var html: String {
        let jsKey = Bundle.main.object(forInfoDictionaryKey: "AMapJSAPIKey") as? String ?? "19f1f3bb82da42e31939daa17688f4be"
        let securityCode = Bundle.main.object(forInfoDictionaryKey: "AMapJSSecurityCode") as? String ?? "977fcb2da98d276b5216b01348e1af3f"
        let active = activeRole == .start ? "start" : "end"

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <style>
            :root { color-scheme: light; }
            * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", sans-serif;
              background: #f3f3f7;
              color: #101116;
            }
            .shell { min-height: 100vh; padding: 54px 18px 22px; }
            .topbar {
              display: grid;
              grid-template-columns: 78px 1fr 92px;
              align-items: center;
              gap: 8px;
              margin-bottom: 18px;
            }
            .title { text-align: center; font-size: 20px; font-weight: 800; }
            button {
              border: 0;
              font: inherit;
              font-weight: 800;
              border-radius: 999px;
              min-height: 50px;
              background: rgba(255,255,255,.92);
              box-shadow: 0 10px 28px rgba(30,40,70,.08);
            }
            .save { background: #101116; color: white; }
            .panel {
              background: rgba(255,255,255,.94);
              border-radius: 28px;
              padding: 14px;
              box-shadow: 0 18px 48px rgba(33,45,73,.10);
              border: 1px solid rgba(0,0,0,.04);
            }
            .field {
              display: grid;
              grid-template-columns: 28px 64px 1fr 58px;
              align-items: center;
              gap: 10px;
              min-height: 62px;
              padding: 0 8px;
              border-radius: 20px;
              background: #f7f8fb;
              margin-bottom: 10px;
              border: 2px solid transparent;
            }
            .field.active { border-color: #20c967; background: #f3fff8; }
            .dot {
              width: 18px; height: 18px; border-radius: 50%;
              background: #20c967; box-shadow: 0 0 0 7px rgba(32,201,103,.12);
              margin-left: 5px;
            }
            .dot.end { background: #2487ff; box-shadow: 0 0 0 7px rgba(36,135,255,.12); }
            label { font-size: 15px; color: #6b7280; font-weight: 800; }
            input {
              width: 100%;
              border: 0;
              outline: 0;
              background: transparent;
              font-size: 16px;
              font-weight: 750;
              color: #111827;
            }
            .mini {
              min-height: 38px;
              border-radius: 14px;
              font-size: 14px;
              color: #0b7f3a;
              background: #dffbea;
              box-shadow: none;
            }
            #map {
              height: 46vh;
              min-height: 360px;
              width: 100%;
              margin-top: 14px;
              border-radius: 28px;
              overflow: hidden;
              background: linear-gradient(135deg,#dff4ff,#e7ffe9);
              box-shadow: inset 0 0 0 1px rgba(0,0,0,.04);
            }
            .hint {
              margin: 14px 4px 0;
              color: #7b8190;
              font-size: 14px;
              line-height: 1.45;
            }
            .results {
              margin-top: 12px;
              display: grid;
              gap: 8px;
              max-height: 22vh;
              overflow: auto;
            }
            .result {
              text-align: left;
              min-height: 54px;
              border-radius: 18px;
              padding: 9px 12px;
              background: rgba(255,255,255,.94);
              box-shadow: none;
            }
            .name { font-weight: 850; font-size: 15px; }
            .addr { margin-top: 3px; color: #777d8c; font-size: 12px; font-weight: 600; }
            .status { margin: 10px 5px 0; color: #5f6675; font-size: 13px; font-weight: 650; }
          </style>
          <script>
            window._AMapSecurityConfig = { securityJsCode: "\(escapeForJavaScript(securityCode))" };
          </script>
          <script src="https://webapi.amap.com/maps?v=2.0&key=\(escapeForJavaScript(jsKey))&plugin=AMap.PlaceSearch,AMap.Geocoder"></script>
        </head>
        <body>
          <div class="shell">
            <div class="topbar">
              <button onclick="postCancel()">取消</button>
              <div class="title">设置通勤路线</div>
              <button class="save" onclick="postSave()">保存路线</button>
            </div>
            <div class="panel">
              <div id="startField" class="field">
                <div class="dot"></div>
                <label>出发地</label>
                <input id="startInput" value="\(escapeForHTML(startAddress))" placeholder="搜地点 / 小区 / 公司">
                <button class="mini" onclick="searchPlace('start')">搜索</button>
              </div>
              <div id="endField" class="field">
                <div class="dot end"></div>
                <label>目的地</label>
                <input id="endInput" value="\(escapeForHTML(endAddress))" placeholder="搜地点 / 公司 / 学校">
                <button class="mini" onclick="searchPlace('end')">搜索</button>
              </div>
              <div id="map"></div>
              <div class="hint">点输入框切换出发地/目的地；搜索后选择结果，或直接点地图设置当前选中的地点。</div>
              <div id="status" class="status"></div>
              <div id="results" class="results"></div>
            </div>
          </div>
          <script>
            let activeRole = "\(active)";
            let map, geocoder, placeSearch;
            let markers = {};
            const selected = {
              start: { address: document.getElementById('startInput').value, lng: null, lat: null },
              end: { address: document.getElementById('endInput').value, lng: null, lat: null }
            };

            function setStatus(text) { document.getElementById('status').textContent = text || ''; }
            function setActive(role) {
              activeRole = role;
              document.getElementById('startField').classList.toggle('active', role === 'start');
              document.getElementById('endField').classList.toggle('active', role === 'end');
            }
            document.getElementById('startField').onclick = (event) => { if (event.target.tagName !== 'BUTTON') setActive('start'); };
            document.getElementById('endField').onclick = (event) => { if (event.target.tagName !== 'BUTTON') setActive('end'); };

            function initMap() {
              map = new AMap.Map('map', { zoom: 12, resizeEnable: true, viewMode: '2D' });
              geocoder = new AMap.Geocoder({ radius: 1000 });
              placeSearch = new AMap.PlaceSearch({ pageSize: 8, pageIndex: 1, extensions: 'all' });
              map.on('click', (event) => {
                const lnglat = event.lnglat;
                geocoder.getAddress(lnglat, (status, result) => {
                  const address = status === 'complete' && result.regeocode ? result.regeocode.formattedAddress : `${lnglat.lng},${lnglat.lat}`;
                  choosePlace(activeRole, address, lnglat.lng, lnglat.lat, address);
                });
              });
              setActive(activeRole);
              setStatus('搜索地点或直接点地图。');
            }

            function searchPlace(role) {
              setActive(role);
              const input = document.getElementById(role === 'start' ? 'startInput' : 'endInput');
              const keyword = input.value.trim();
              if (!keyword) { setStatus('请先输入地点关键词。'); return; }
              setStatus('正在调用高德搜索...');
              placeSearch.search(keyword, (status, result) => {
                const list = document.getElementById('results');
                list.innerHTML = '';
                if (status !== 'complete' || !result.poiList || !result.poiList.pois.length) {
                  setStatus('没有搜到地点，请输入更完整的地址。');
                  return;
                }
                setStatus(`找到 ${result.poiList.pois.length} 个结果，请选择一个。`);
                result.poiList.pois.forEach((poi) => {
                  const item = document.createElement('button');
                  item.className = 'result';
                  item.innerHTML = `<div class="name">${poi.name}</div><div class="addr">${poi.address || poi.pname || ''}</div>`;
                  item.onclick = () => choosePlace(role, poi.name, poi.location.lng, poi.location.lat, poi.address || poi.name);
                  list.appendChild(item);
                });
              });
            }

            function choosePlace(role, name, lng, lat, address) {
              selected[role] = { address: name || address, lng, lat };
              document.getElementById(role === 'start' ? 'startInput' : 'endInput').value = selected[role].address;
              if (markers[role]) map.remove(markers[role]);
              markers[role] = new AMap.Marker({
                position: [lng, lat],
                title: role === 'start' ? '出发地' : '目的地',
                label: { content: role === 'start' ? '出发地' : '目的地', direction: 'top' }
              });
              map.add(markers[role]);
              map.setCenter([lng, lat]);
              map.setZoom(16);
              setStatus(`${role === 'start' ? '出发地' : '目的地'}已选择：${selected[role].address}`);
            }

            function postCancel() {
              window.webkit.messageHandlers.routePicker.postMessage({ type: 'cancel' });
            }
            function postSave() {
              const startAddress = document.getElementById('startInput').value.trim();
              const endAddress = document.getElementById('endInput').value.trim();
              if (!startAddress || !endAddress) {
                setStatus('请先设置出发地和目的地。');
                return;
              }
              window.webkit.messageHandlers.routePicker.postMessage({
                type: 'save',
                startAddress,
                endAddress
              });
            }

            if (window.AMap) {
              initMap();
            } else {
              setStatus('高德地图加载失败，请检查网络或 JS API Key。');
            }
          </script>
        </body>
        </html>
        """
    }

    private func escapeForHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
