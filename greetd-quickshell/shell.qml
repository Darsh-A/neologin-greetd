import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

// neo-login: neobrutal mono "tech" greeter for greetd + Quickshell.
// Settings live in config.json (override: /etc/neo-login/config.json).
// Demo mode (no greetd socket): password "open" succeeds, anything else fails, Esc quits.
ShellRoot {
    id: root

    // ---------------- config (config.json, or /etc/neo-login/config.json) ----------------
    property var cfg: ({})
    property string detectedUser: ""
    readonly property string themeDir: Qt.resolvedUrl(".").toString().replace("file://", "")

    readonly property string userName: cfg.user ? cfg.user : detectedUser
    readonly property string displayName: (cfg.displayName ? cfg.displayName : userName).toUpperCase()
    readonly property string avatar: cfg.avatar ? cfg.avatar : "/var/lib/AccountsService/icons/" + userName
    readonly property int maxAttempts: cfg.maxAttempts > 0 ? cfg.maxAttempts : 3
    readonly property int lockoutSeconds: cfg.lockoutSeconds >= 0 ? cfg.lockoutSeconds : 5
    readonly property bool animSuccess: !cfg.animations || cfg.animations.success !== false
    readonly property bool animAlarm: !cfg.animations || cfg.animations.alarm !== false
    readonly property bool showHost: cfg.showHost !== false
    property bool inverted: true          // chip in the corner toggles it at runtime

    FontLoader { source: Qt.resolvedUrl("fonts/SpaceMono-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("fonts/SpaceMono-Bold.ttf") }
    FontLoader { source: Qt.resolvedUrl("fonts/ArchivoBlack-Regular.ttf") }

    readonly property bool red: warn || alarm
    readonly property color fg: red ? "#ff2a2a" : (inverted ? "#f2f2ee" : "#0b0b0b")
    readonly property color bg: red ? (alarm && pulse ? "#2e0000" : "#140000") : (inverted ? "#0b0b0b" : "#f2f2ee")

    // ---------------- state ----------------
    property var sessions: []             // [{ name, exec }]
    property int sessionIndex: 0
    readonly property string sessionName: sessions.length > sessionIndex ? sessions[sessionIndex].name : "SESSION"
    property string status: "> AWAITING INPUT_"
    property string pendingPassword: ""
    property bool busy: false
    property int shakeTick: 0
    property string hostName: ""

    // failed-login alarm (visual, plus a short input lockout; real protection is PAM faillock)
    readonly property string defaultHeader: "AUTHENTICATION // 認証"
    readonly property string defaultTitle: "⚠ INTRUDER DETECTED ⚠ SELF-DESTRUCT INITIATED ⚠"
    readonly property var alarmMsgs: ["UNAUTHORIZED ACCESS LOGGED", "SECURITY KEYS REVOKED", "TRACING ORIGIN…",
        "ISOLATING SESSION", "PURGING SESSION CACHE", "DEPLOYING COUNTERMEASURES",
        "SEVERING NETWORK LINK", "DATA SHREDDER ARMED", "SAY GOODBYE", "NO TURNING BACK"]
    property int fails: 0
    property bool locked: false
    property bool warn: false
    property bool alarm: false
    property bool pulse: false
    property string phase: ""             // "", "count", "lockout"
    property int counter: 10
    property string headerLeft: defaultHeader
    property string overlayTitle: defaultTitle
    property string overlayMsg: ""
    readonly property string cdText: (counter < 10 ? "0" : "") + counter

    // success sequence
    property bool granting: false
    property bool grantFin: false
    property int grantStep: 0
    property var grantSteps: []
    readonly property int grantPct: grantSteps.length > 0 ? Math.round(100 * Math.min(grantStep, grantSteps.length) / grantSteps.length) : 0

    // ---------------- logic ----------------
    function cycle(d) {
        if (sessions.length > 0)
            sessionIndex = (sessionIndex + d + sessions.length) % sessions.length;
    }

    function boot() {
        const dirs = (cfg.sessionDirs && cfg.sessionDirs.length) ? cfg.sessionDirs : ["/usr/share/wayland-sessions"];
        sessionsProc.command = ["sh", "-c", "for f in " + dirs.map(d => "'" + d + "'/*.desktop").join(" ")
            + "; do [ -f \"$f\" ] || continue; n=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); e=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-); [ -n \"$e\" ] && echo \"$n|$e\"; done"];
        sessionsProc.running = true;
        if (!cfg.user) userProc.running = true;
        hostProc.running = true;
    }

    function flash(ms, label) {
        warn = true;
        headerLeft = label;
        warnTimer.interval = ms;
        warnTimer.restart();
    }

    function updateOverlay() {
        if (phase === "count")
            overlayMsg = counter > 0 ? "> " + alarmMsgs[10 - counter] : "> ░░ PURGE COMPLETE ░░";
        else if (phase === "lockout")
            overlayMsg = "> SEQUENCE ABORTED. LOCKOUT " + counter + "s";
    }

    function startDestruct() {
        locked = true;
        if (!animAlarm) {                 // plain lockout, no theatrics
            phase = "lockout";
            counter = lockoutSeconds;
            status = "> LOCKED. RETRY IN " + counter + "s";
            return;
        }
        alarm = true; pulse = false;
        phase = "count"; counter = 10;
        headerLeft = "!! BREACH !!";
        overlayTitle = defaultTitle;
        updateOverlay();
    }

    function resetAlarm() {
        alarm = false; warn = false; pulse = false; phase = ""; locked = false; fails = 0;
        counter = 10; headerLeft = defaultHeader; overlayTitle = defaultTitle;
        status = "> AWAITING INPUT_";
    }

    function registerFail(why) {
        const tag = why ? " [" + String(why).toUpperCase().slice(0, 40) + "]" : "";
        fails++;
        shakeTick++;
        const left = maxAttempts - fails;
        if (left <= 0) { status = "> HOSTILE ACCESS CONFIRMED."; startDestruct(); }
        else if (left === 1) { status = "> FINAL WARNING. 1 RETRY LEFT." + tag; flash(1400, "!! WARNING !!"); }
        else { status = "> ACCESS DENIED. " + left + " RETRIES LEFT." + tag; flash(700, "!! DENIED !!"); }
    }

    function launchSession() {
        if (Greetd.available) {
            Greetd.launch(["sh", "-c", sessions[sessionIndex].exec], [], true);
        } else {                          // demo mode: just reset
            granting = false; grantFin = false; grantStep = 0; fails = 0;
            status = "> AWAITING INPUT_";
        }
    }

    function startGrant() {
        grantSteps = ["VERIFYING IDENTITY", "DECRYPTING KEYRING", "SYNCHRONIZING SESSION",
                      "MOUNTING WORKSPACE", "STARTING " + sessionName.toUpperCase()];
        grantStep = 0;
        grantFin = false;
        granting = true;
        grantTimer.interval = 450;
        grantTimer.restart();
    }

    function attempt(pw) {
        if (busy || locked || granting) return;
        if (pw === "") { status = "> ENTER PASSCODE."; shakeTick++; return; }
        if (!Greetd.available) {          // demo mode: "open" succeeds, anything else fails
            if (pw === "open") {
                fails = 0;
                if (animSuccess) startGrant(); else status = "> DEMO: ACCESS GRANTED.";
            } else registerFail();
            return;
        }
        if (sessions.length === 0) { status = "> NO SESSIONS FOUND."; return; }
        pendingPassword = pw;
        busy = true;
        status = "> VERIFYING_";
        Greetd.createSession(userName);
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            console.log("greetd authMessage:", JSON.stringify(message), "error=" + error, "responseRequired=" + responseRequired);
            if (responseRequired) {
                Greetd.respond(root.pendingPassword);
                root.pendingPassword = "";
            } else {
                root.status = "> " + message.toUpperCase();
            }
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.pendingPassword = "";
            console.log("greetd authFailure:", JSON.stringify(message));
            root.registerFail(message);
        }
        function onReadyToLaunch() {
            root.busy = false;
            root.status = "> ACCESS GRANTED.";
            if (root.animSuccess) root.startGrant(); else root.launchSession();
        }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    Timer { id: warnTimer; onTriggered: { if (!root.alarm) { root.warn = false; root.headerLeft = root.defaultHeader; } } }
    Timer { interval: 250; repeat: true; running: root.alarm; onTriggered: root.pulse = !root.pulse }
    Timer {
        interval: 1000; repeat: true; running: root.phase !== ""
        onTriggered: {
            root.counter--;
            if (root.counter < 0) {
                if (root.phase === "count") {
                    root.phase = "lockout";
                    root.counter = root.lockoutSeconds;
                    root.overlayTitle = "SIMULATION ONLY // NOTHING WAS HARMED";
                } else {
                    root.resetAlarm();
                    return;
                }
            }
            if (root.alarm) root.updateOverlay();
            else root.status = "> LOCKED. RETRY IN " + root.counter + "s";
        }
    }
    Timer {
        id: grantTimer
        onTriggered: {
            if (root.grantFin) { root.launchSession(); return; }
            if (root.grantStep < root.grantSteps.length) {
                root.grantStep++;
                interval = 380;
            } else {
                root.grantFin = true;
                interval = 900;
            }
            restart();
        }
    }

    // ---------------- startup: config -> sessions / user / host ----------------
    Process {
        running: true
        command: ["sh", "-c", "cat /etc/neo-login/config.json 2>/dev/null || cat \"$1\" 2>/dev/null", "sh", root.themeDir + "config.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.cfg = JSON.parse(text); }
                catch (e) { console.log("neo-login: bad or missing config.json, using defaults:", e); root.cfg = ({}); }
                root.inverted = root.cfg.inverted !== false;
                root.boot();
            }
        }
    }

    Process {
        id: sessionsProc
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.trim().split("\n").filter(l => l.length > 0).map(l => {
                    const i = l.indexOf("|");
                    return { name: l.slice(0, i), exec: l.slice(i + 1) };
                });
                root.sessions = list;
                const pref = String(root.cfg.defaultSession || "hyprland").toLowerCase();
                const h = list.findIndex(x => x.name.toLowerCase().indexOf(pref) >= 0 || x.exec.toLowerCase().indexOf(pref) >= 0);
                root.sessionIndex = h < 0 ? 0 : h;
            }
        }
    }

    Process {
        id: userProc
        command: ["sh", "-c", "awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1; exit}' /etc/passwd"]
        stdout: StdioCollector { onStreamFinished: root.detectedUser = text.trim() }
    }

    Process {
        id: hostProc
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: root.hostName = text.trim() }
    }

    // ---------------- reusable bits ----------------
    component Stripes: Canvas {
        property color ink
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.clearRect(0, 0, width, height);
            c.fillStyle = ink;
            for (let x = -height; x < width + height; x += 20) {
                c.beginPath();
                c.moveTo(x, height); c.lineTo(x + 10, height);
                c.lineTo(x + 10 + height, 0); c.lineTo(x + height, 0);
                c.closePath(); c.fill();
            }
        }
    }

    component Btn: Item {
        id: btn
        property string label
        property string sub: ""
        property color fg
        property color bg
        property bool solid: false
        signal clicked()
        readonly property bool inv: solid !== ma.containsMouse
        implicitWidth: col.implicitWidth + 28
        implicitHeight: sub === "" ? 40 : 48

        Rectangle { x: 5; y: 5; width: btn.width; height: btn.height; color: btn.fg }
        Rectangle {
            x: ma.pressed ? 5 : 0
            y: ma.pressed ? 5 : 0
            width: btn.width; height: btn.height
            color: btn.inv ? btn.fg : btn.bg
            border.width: 4
            border.color: btn.fg
            Column {
                id: col
                anchors.centerIn: parent
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: btn.label
                    color: btn.inv ? btn.bg : btn.fg
                    font.family: "Space Mono"; font.bold: true; font.pixelSize: 13; font.letterSpacing: 1
                }
                Text {
                    visible: btn.sub !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: btn.sub
                    color: btn.inv ? btn.bg : btn.fg
                    opacity: 0.7
                    font.pixelSize: 10
                }
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
    }

    // ---------------- one window per screen ----------------
    Variants {
        model: [0]    // single window: cage shows one fullscreen toplevel

        FloatingWindow {
            id: win
            readonly property bool primary: true
            property bool reveal: false
            implicitWidth: 1280     // only used when testing outside cage
            implicitHeight: 720
            visible: true
            color: root.bg

            Item {
                anchors.fill: parent
                Keys.onEscapePressed: if (!Greetd.available) Qt.quit()

                // grid
                Canvas {
                    anchors.fill: parent
                    opacity: 0.14
                    property color ink: root.fg
                    onInkChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d");
                        c.clearRect(0, 0, width, height);
                        c.strokeStyle = ink; c.lineWidth = 1; c.beginPath();
                        for (let x = 0; x < width; x += 48) { c.moveTo(x + 0.5, 0); c.lineTo(x + 0.5, height); }
                        for (let y = 0; y < height; y += 48) { c.moveTo(0, y + 0.5); c.lineTo(width, y + 0.5); }
                        c.stroke();
                    }
                }

                // giant outlined kanji
                Text {
                    anchors.centerIn: parent
                    text: "認証"
                    font.pixelSize: parent.height * 0.7
                    font.family: "Archivo Black"
                    color: "transparent"
                    style: Text.Outline
                    styleColor: root.fg
                    opacity: 0.12
                }

                // scanlines
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const c = getContext("2d");
                        c.clearRect(0, 0, width, height);
                        c.fillStyle = "rgba(0,0,0,0.05)";
                        for (let y = 0; y < height; y += 4) c.fillRect(0, y, width, 1);
                    }
                }

                // clock
                Rectangle {
                    x: 24; y: 24
                    opacity: root.alarm ? 0.25 : 1
                    width: clockCol.implicitWidth + 32
                    height: clockCol.implicitHeight + 20
                    color: root.fg
                    border.width: 4; border.color: root.fg
                    Column {
                        id: clockCol
                        anchors.centerIn: parent
                        Text {
                            text: Qt.formatDateTime(clock.date, "HH:mm")
                            color: root.bg
                            font.family: "Archivo Black"; font.pixelSize: 56
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "yyyy-MM-dd") + " · "
                                  + ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"][clock.date.getDay()]
                            color: root.bg
                            font.family: "Space Mono"; font.pixelSize: 12; font.letterSpacing: 2
                        }
                    }
                }

                // top-right chips
                Row {
                    anchors { top: parent.top; right: parent.right; margins: 24 }
                    opacity: root.alarm ? 0.25 : 1
                    spacing: 12
                    Rectangle {
                        visible: root.showHost && root.hostName !== ""
                        width: hostTxt.implicitWidth + 20; height: 32
                        color: root.bg; border.width: 3; border.color: root.fg
                        Text {
                            id: hostTxt
                            anchors.centerIn: parent
                            text: "HOST:" + root.hostName.toUpperCase()
                            color: root.fg
                            font.family: "Space Mono"; font.bold: true; font.pixelSize: 12
                        }
                    }
                    Btn { fg: root.fg; bg: root.bg; label: "◐ INVERT"; onClicked: root.inverted = !root.inverted }
                }

                // ---------------- auth card ----------------
                Item {
                    id: card
                    visible: win.primary
                    anchors.centerIn: parent
                    width: Math.min(440, parent.width - 40)
                    height: cardBody.implicitHeight + 8
                    property real shakeX: 0
                    property real jit: 0
                    transform: Translate { x: card.shakeX + card.jit }

                    Connections {
                        target: root
                        function onShakeTickChanged() { shake.restart(); pw.text = ""; }
                    }
                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: card; property: "shakeX"; to: -12; duration: 50 }
                        NumberAnimation { target: card; property: "shakeX"; to: 12; duration: 80 }
                        NumberAnimation { target: card; property: "shakeX"; to: -7; duration: 70 }
                        NumberAnimation { target: card; property: "shakeX"; to: 7; duration: 60 }
                        NumberAnimation { target: card; property: "shakeX"; to: 0; duration: 50 }
                    }

                    SequentialAnimation {
                        running: root.alarm
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) card.jit = 0
                        NumberAnimation { target: card; property: "jit"; to: 3; duration: 50 }
                        NumberAnimation { target: card; property: "jit"; to: -3; duration: 100 }
                        NumberAnimation { target: card; property: "jit"; to: 0; duration: 50 }
                    }

                    Rectangle { x: 10; y: 10; width: parent.width; height: parent.height; color: root.fg }
                    Rectangle { anchors.fill: parent; color: root.bg; border.width: 4; border.color: root.fg }

                    ColumnLayout {
                        id: cardBody
                        x: 4; y: 4
                        width: parent.width - 8
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 30
                            color: root.fg
                            Text {
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: root.headerLeft
                                color: root.bg
                                font.family: "Space Mono"; font.bold: true; font.pixelSize: 12; font.letterSpacing: 2
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: root.alarm ? "● COMPROMISED" : (Greetd.available ? "● LINK OK" : "● DEMO")
                                color: root.bg
                                font.family: "Space Mono"; font.bold: true; font.pixelSize: 12; font.letterSpacing: 2
                            }
                        }
                        Stripes { Layout.fillWidth: true; Layout.preferredHeight: 12; ink: root.fg }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 4; color: root.fg }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: body.implicitHeight + 40

                            ColumnLayout {
                                id: body
                                x: 16; y: 20
                                width: parent.width - 32
                                spacing: 14

                                // who
                                RowLayout {
                                    spacing: 16
                                    Rectangle {
                                        Layout.preferredWidth: 88; Layout.preferredHeight: 88
                                        color: root.fg; border.width: 4; border.color: root.fg
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.displayName.charAt(0)
                                            color: root.bg
                                            font.family: "Archivo Black"; font.pixelSize: 44
                                        }
                                        Image {
                                            anchors.fill: parent
                                            source: root.avatar !== "" ? "file://" + root.avatar : ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: status === Image.Ready
                                        }
                                    }
                                    Column {
                                        Text { text: "OPERATOR"; color: root.fg; opacity: 0.7; font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 2 }
                                        Text { text: root.displayName; color: root.fg; font.family: "Archivo Black"; font.pixelSize: 30 }
                                        Text { text: "UID:" + root.userName.toUpperCase(); color: root.fg; opacity: 0.7; font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 2 }
                                    }
                                }

                                Text { text: "PASSCODE"; color: root.fg; opacity: 0.7; font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 2 }

                                // password row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: 44
                                        color: pw.activeFocus ? root.fg : root.bg
                                        border.width: 4; border.color: root.fg
                                        Text {
                                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                            visible: pw.text === ""
                                            text: "••••••••"
                                            color: pw.activeFocus ? root.bg : root.fg
                                            opacity: 0.4
                                            font.family: "Space Mono"; font.pixelSize: 16; font.letterSpacing: 3
                                        }
                                        TextInput {
                                            id: pw
                                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: win.reveal ? TextInput.Normal : TextInput.Password
                                            passwordCharacter: "•"
                                            readOnly: root.busy || root.locked || root.granting
                                            focus: win.primary
                                            clip: true
                                            color: activeFocus ? root.bg : root.fg
                                            selectionColor: root.bg
                                            selectedTextColor: root.fg
                                            font.family: "Space Mono"; font.bold: true; font.pixelSize: 16; font.letterSpacing: 3
                                            onAccepted: root.attempt(text)
                                            Keys.onTabPressed: root.cycle(1)
                                            Keys.onBacktabPressed: root.cycle(-1)
                                        }
                                    }
                                    Btn { fg: root.fg; bg: root.bg; label: "◉"; onClicked: win.reveal = !win.reveal }
                                    Btn { fg: root.fg; bg: root.bg; label: "EXECUTE ▶"; solid: true; onClicked: root.attempt(pw.text) }
                                }

                                // sync bar
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    readonly property int pct: Math.min(100, pw.text.length * 12)
                                    Text {
                                        text: "SYNC RATE " + String(parent.pct).padStart(3, "0") + "%"
                                        color: root.fg; opacity: 0.7
                                        font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 2
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: 16
                                        color: root.bg; border.width: 3; border.color: root.fg
                                        Rectangle {
                                            x: 3; y: 3; height: parent.height - 6
                                            width: (parent.width - 6) * parent.parent.pct / 100
                                            color: root.fg
                                            Behavior on width { NumberAnimation { duration: 150 } }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.status
                                    color: root.fg
                                    elide: Text.ElideRight
                                    font.family: "Space Mono"; font.bold: true; font.pixelSize: 13; font.letterSpacing: 1
                                }

                                Text { text: "RETRIES  " + "▮".repeat(Math.max(0, root.maxAttempts - root.fails)) + "▯".repeat(Math.min(root.fails, root.maxAttempts)); color: root.fg; opacity: 0.7; font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 2 }

                                Text { text: "SESSION // 環境"; color: root.fg; opacity: 0.7; font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 2 }

                                // <= 3 sessions: segmented tabs
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.sessions.length <= 3
                                    spacing: -3
                                    Repeater {
                                        model: root.sessions
                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true; Layout.preferredHeight: 38
                                            color: index === root.sessionIndex ? root.fg : root.bg
                                            border.width: 3; border.color: root.fg
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.name.toUpperCase()
                                                color: index === root.sessionIndex ? root.bg : root.fg
                                                font.family: "Space Mono"; font.bold: true; font.pixelSize: 12
                                            }
                                            MouseArea { anchors.fill: parent; onClicked: root.sessionIndex = index }
                                        }
                                    }
                                }

                                // > 3 sessions: arrow selector
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.sessions.length > 3
                                    spacing: 12
                                    Btn { fg: root.fg; bg: root.bg; label: "◀"; onClicked: root.cycle(-1) }
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: 40
                                        color: root.fg
                                        Text {
                                            anchors.centerIn: parent
                                            text: (root.sessions[root.sessionIndex] ? root.sessions[root.sessionIndex].name.toUpperCase() : "")
                                                  + "  " + (root.sessionIndex + 1) + "/" + root.sessions.length
                                            color: root.bg
                                            elide: Text.ElideRight
                                            font.family: "Space Mono"; font.bold: true; font.pixelSize: 12
                                        }
                                    }
                                    Btn { fg: root.fg; bg: root.bg; label: "▶"; onClicked: root.cycle(1) }
                                }
                            }
                        }
                    }
                }

                // ---------------- alarm overlay ----------------
                Item {
                    anchors.fill: parent
                    visible: root.alarm

                    Canvas {
                        anchors.fill: parent
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d");
                            c.clearRect(0, 0, width, height);
                            const g = c.createRadialGradient(width / 2, height / 2, Math.min(width, height) * 0.35,
                                                             width / 2, height / 2, Math.max(width, height) * 0.75);
                            g.addColorStop(0, "rgba(255,0,0,0)");
                            g.addColorStop(1, "rgba(255,0,0,0.47)");
                            c.fillStyle = g;
                            c.fillRect(0, 0, width, height);
                        }
                        SequentialAnimation on opacity {
                            running: root.alarm; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }

                    Text {
                        anchors { top: parent.top; topMargin: 70; horizontalCenter: parent.horizontalCenter }
                        width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.overlayTitle
                        color: root.fg
                        font.family: "Space Mono"; font.bold: true; font.pixelSize: 20; font.letterSpacing: 6
                        SequentialAnimation on opacity {
                            running: root.alarm; loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 250 }
                            NumberAnimation { to: 1; duration: 250 }
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: cdTxt.implicitWidth; height: cdTxt.implicitHeight
                        transform: Translate { id: glitch }
                        SequentialAnimation {
                            running: root.alarm; loops: Animation.Infinite
                            NumberAnimation { target: glitch; property: "x"; to: 4; duration: 125 }
                            NumberAnimation { target: glitch; property: "x"; to: 0; duration: 125 }
                        }
                        Text {
                            id: cdTxt
                            text: root.cdText
                            color: root.fg
                            font.family: "Archivo Black"
                            font.pixelSize: Math.min(win.width * 0.24, 240)
                        }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; bottomMargin: 130; horizontalCenter: parent.horizontalCenter }
                        width: ovMsg.implicitWidth + 28; height: ovMsg.implicitHeight + 12
                        color: root.fg
                        Text {
                            id: ovMsg
                            anchors.centerIn: parent
                            text: root.overlayMsg
                            color: root.bg
                            font.family: "Space Mono"; font.bold: true; font.pixelSize: 18; font.letterSpacing: 3
                        }
                    }
                }

                // hint
                Text {
                    visible: win.primary
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 24; bottomMargin: 56 }
                    text: "TAB: SESSION · ENTER: EXECUTE"
                    color: root.fg; opacity: 0.7
                    font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 1
                }

                // power
                Row {
                    visible: win.primary
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 29; bottomMargin: 61 }
                    spacing: 14
                    Btn { fg: root.fg; bg: root.bg; label: "SUSPEND"; sub: "待機"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
                    Btn { fg: root.fg; bg: root.bg; label: "REBOOT"; sub: "再起動"; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
                    Btn { fg: root.fg; bg: root.bg; label: "SHUTDOWN"; sub: "停止"; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
                }

                // caution tape (scroll offset is a looping 0..1 phase, so it never depends on layout timing)
                Rectangle {
                    id: tapeBar
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 34
                    color: root.fg
                    clip: true
                    readonly property string unit: root.alarm
                        ? "DANGER // INTRUDER DETECTED // 侵入者検知 // LOCKDOWN IN PROGRESS // "
                        : "CAUTION // AUTHENTICATION REQUIRED // 警告 // UNAUTHORIZED ACCESS WILL BE LOGGED // "
                    property real phase: 0

                    NumberAnimation on phase { from: 0; to: 1; duration: 18000; loops: Animation.Infinite; running: true }

                    TextMetrics {
                        id: tapeUnit
                        text: tapeBar.unit
                        font.family: "Space Mono"; font.bold: true; font.pixelSize: 13; font.letterSpacing: 4
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: -tapeBar.phase * tapeUnit.advanceWidth
                        text: tapeBar.unit.repeat(12)
                        color: root.bg
                        font: tapeUnit.font
                    }
                }

                // ---------------- success sequence ----------------
                Item {
                    id: grant
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: root.granting ? parent.width : 0
                    visible: width > 0
                    clip: true
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
                    readonly property color ink: root.grantFin ? root.bg : root.fg

                    Rectangle { anchors.fill: parent; color: root.grantFin ? root.fg : root.bg }
                    MouseArea { anchors.fill: parent }

                    Item {
                        width: win.width
                        height: parent.height
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 18
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: root.grantFin ? "WELCOME,\n" + root.displayName : "ACCESS GRANTED"
                                color: grant.ink
                                font.family: "Archivo Black"; font.pixelSize: Math.min(win.width * 0.1, 84)
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.grantFin ? "LAUNCHING SESSION…" : "認証完了 // LINK ESTABLISHED"
                                color: grant.ink
                                font.family: "Space Mono"; font.pixelSize: 13; font.letterSpacing: 6
                            }
                            Column {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: Math.min(460, win.width * 0.9)
                                Layout.preferredHeight: 128
                                spacing: 6
                                Repeater {
                                    model: Math.min(root.grantStep, root.grantSteps.length)
                                    Text {
                                        required property int index
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "> " + root.grantSteps[index] + " " + ((index < root.grantStep - 1 || root.grantFin) ? "[ OK ]" : "…")
                                        color: grant.ink
                                        font.family: "Space Mono"; font.bold: true; font.pixelSize: 14; font.letterSpacing: 1
                                    }
                                }
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: Math.min(460, win.width * 0.9)
                                Layout.preferredHeight: 22
                                color: "transparent"; border.width: 4; border.color: grant.ink
                                Rectangle {
                                    x: 4; y: 4; height: parent.height - 8
                                    width: (parent.width - 8) * root.grantPct / 100
                                    color: grant.ink
                                    Behavior on width { NumberAnimation { duration: 350 } }
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "SYNC RATE " + String(root.grantPct).padStart(3, "0") + "%"
                                color: grant.ink; opacity: 0.7
                                font.family: "Space Mono"; font.pixelSize: 11; font.letterSpacing: 2
                            }
                        }
                    }
                }
            }
        }
    }
}
