<%@ page language="C" contentType="text/html; charset=UTF-8"%>
<!DOCTYPE html>
<html>
<head>
<title>Stability Framework</title>
<meta http-equiv="X-UA-Compatible" content="IE=Edge"/>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
<meta HTTP-EQUIV="Pragma" CONTENT="no-cache">
<meta HTTP-EQUIV="Expires" CONTENT="-1">
<link rel="shortcut icon" href="images/favicon.png">
<link rel="stylesheet" type="text/css" href="index_style.css">
<link rel="stylesheet" type="text/css" href="form_style.css">
<script>
// Merlin Canonical Settings Injection
var custom_settings = <% get_custom_settings(); %>;
</script>
<style>
.status-card { background: #fdfdfd; border: 1px solid #ccc; padding: 15px; border-radius: 5px; margin-bottom: 10px; }
.ok { color: #28a745; font-weight: bold; }
.fail { color: #dc3545; font-weight: bold; }
.metric { font-size: 1.2em; font-family: monospace; }
</style>
</head>
<body>
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>

<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

<form method="post" name="form" action="apply.cgi" target="hidden_frame">
<input type="hidden" name="current_page" value="stability.asp">
<input type="hidden" name="next_page" value="stability.asp">
<input type="hidden" name="action_mode" value="apply">
<input type="hidden" name="action_script" value="restart_stability_addon">
<input type="hidden" name="action_wait" value="5">

<table class="content_bg" cellpadding="0" cellspacing="0">
    <tr>
        <td width="17">&nbsp;</td>
        <td valign="top" width="202">
            <div id="mainMenu"></div>
            <div id="subMenu"></div>
        </td>
        <td valign="top">
            <div id="tabMenu" class="submenuBlock"></div>

            <table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
                <tr>
                    <td valign="top">
                        <h2>Stability Framework v2.0</h2>

                        <div class="status-card">
                            <h3>Tether Cloak Status</h3>
                            <table width="100%">
                                <tr><td>IPv4 TTL:</td><td id="ttl" class="metric">Loading...</td></tr>
                                <tr><td>IPv6 Hop Limit:</td><td id="hl" class="metric">Loading...</td></tr>
                                <tr><td>WAN MTU:</td><td id="mtu" class="metric">Loading...</td></tr>
                                <tr><td>Active Interface:</td><td id="wan" class="metric">Loading...</td></tr>
                            </table>
                        </div>

                        <div class="status-card">
                            <h3>System Health</h3>
                            <table width="100%">
                                <tr><td>Time Sync:</td><td id="time_status" class="metric">Checking...</td></tr>
                                <tr><td>Service Monitor:</td><td id="svc_status" class="metric">Active</td></tr>
                            </table>
                        </div>

                        <div style="margin-top: 10px;">
                            <input type="button" class="button_gen" onclick="reloadRules()" value="Reload Rules">
                        </div>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</form>

<script>
function reloadRules() {
    document.form.submit();
    setTimeout(function() { location.reload(); }, 2000);
}

function checkStatus() {
    // Check TTL Rule Presence
    var xhr = new XMLHttpRequest();
    xhr.open('GET', 'shell.cgi?cmd=iptables -t mangle -L POSTROUTING -n | grep -c "TTL set"', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState == 4) {
            var active = parseInt(xhr.responseText) > 0;
            document.getElementById('ttl').innerHTML = active ? '<span class="ok">ACTIVE</span>' : '<span class="fail">INACTIVE</span>';
        }
    };
    xhr.send();

    // Check Interface
    var xhr2 = new XMLHttpRequest();
    xhr2.open('GET', 'shell.cgi?cmd=ip link show usb0 >/dev/null 2>&1 && echo usb0 || echo eth8', true);
    xhr2.onreadystatechange = function() {
        if (xhr2.readyState == 4) {
            document.getElementById('wan').innerText = xhr2.responseText.trim() || "None";
        }
    };
    xhr2.send();
}

// Initial Load
setInterval(checkStatus, 5000);
checkStatus();
</script>
</body>
</html>
