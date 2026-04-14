// VibeOS SDDM login theme
// Neon Grid — magenta + cyan + violet, VibeOS wordmark
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // --- config bindings ---
    property string cfgBackground: config.background
    property color  cfgPrimary:    config.primaryColor    || "#FF2ECF"
    property color  cfgAccent:     config.accentColor     || "#01F9FF"
    property color  cfgSecondary:  config.secondaryColor  || "#9D4EDD"
    property color  cfgText:       config.textColor       || "#F8F0FF"
    property color  cfgMuted:      config.mutedTextColor  || "#B5A6D9"
    property color  cfgBg:         config.backgroundColor || "#0B0218"
    property color  cfgPositive:   config.positiveColor   || "#05FFA1"
    property color  cfgNegative:   config.negativeColor   || "#FF6188"
    property string cfgFont:       config.font            || "Orbitron"
    property string cfgMonoFont:   config.monoFont        || "JetBrains Mono"

    // --- background: image if set, else radial neon gradient ---
    Rectangle {
        anchors.fill: parent
        color: root.cfgBg

        Image {
            id: bgImage
            anchors.fill: parent
            source: root.cfgBackground
            fillMode: Image.PreserveAspectCrop
            opacity: status === Image.Ready ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        // Tron grid overlay (always visible, subtle)
        Canvas {
            anchors.fill: parent
            opacity: 0.18
            onPaint: {
                const ctx = getContext("2d");
                ctx.strokeStyle = root.cfgAccent;
                ctx.lineWidth = 1;
                const step = 64;
                for (let x = 0; x < width; x += step) {
                    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                }
                for (let y = 0; y < height; y += step) {
                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                }
            }
        }
    }

    // --- wordmark ---
    Text {
        id: wordmark
        anchors.top: parent.top
        anchors.topMargin: 80
        anchors.horizontalCenter: parent.horizontalCenter
        text: "VibeOS"
        color: root.cfgPrimary
        font.family: root.cfgFont
        font.pixelSize: 96
        font.bold: true
        style: Text.Raised
        styleColor: root.cfgAccent
    }

    Text {
        anchors.top: wordmark.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        text: "neon grid // 0.4.0"
        color: root.cfgMuted
        font.family: root.cfgMonoFont
        font.pixelSize: 20
    }

    // --- login card ---
    Rectangle {
        id: card
        width: 420
        height: 320
        anchors.centerIn: parent
        color: Qt.rgba(0.05, 0.01, 0.1, 0.85)
        border.color: root.cfgPrimary
        border.width: 2
        radius: 16

        // Neon rim glow
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            color: "transparent"
            border.color: root.cfgAccent
            border.width: 1
            radius: parent.radius + 4
            opacity: 0.35
            z: -1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 18

            ComboBox {
                id: userField
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                model: userModel
                currentIndex: userModel.lastIndex
                textRole: "name"
                font.family: root.cfgFont
                font.pixelSize: 18

                delegate: ItemDelegate {
                    width: userField.width
                    contentItem: Text {
                        text: name
                        color: root.cfgText
                        font: userField.font
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: highlighted ? root.cfgPrimary : Qt.rgba(0.1, 0.04, 0.2, 0.95)
                    }
                }

                contentItem: Text {
                    text: userField.displayText
                    color: root.cfgText
                    font: userField.font
                    leftPadding: 12
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    color: Qt.rgba(0.1, 0.04, 0.2, 0.95)
                    border.color: userField.activeFocus ? root.cfgPrimary : root.cfgSecondary
                    border.width: 2
                    radius: 8
                }
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                echoMode: TextInput.Password
                placeholderText: "password"
                placeholderTextColor: root.cfgMuted
                color: root.cfgText
                font.family: root.cfgMonoFont
                font.pixelSize: 18
                leftPadding: 12

                background: Rectangle {
                    color: Qt.rgba(0.1, 0.04, 0.2, 0.95)
                    border.color: passwordField.activeFocus ? root.cfgPrimary : root.cfgSecondary
                    border.width: 2
                    radius: 8

                    // Magenta focus glow
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        color: "transparent"
                        border.color: root.cfgPrimary
                        border.width: 2
                        radius: parent.radius + 3
                        opacity: passwordField.activeFocus ? 0.6 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        z: -1
                    }
                }

                Keys.onReturnPressed: sddm.login(userField.currentText, passwordField.text, sessionField.currentIndex)
                Keys.onEnterPressed: sddm.login(userField.currentText, passwordField.text, sessionField.currentIndex)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ComboBox {
                    id: sessionField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    model: sessionModel
                    currentIndex: sessionModel.lastIndex
                    textRole: "name"
                    font.family: root.cfgFont
                    font.pixelSize: 14

                    contentItem: Text {
                        text: sessionField.displayText
                        color: root.cfgText
                        font: sessionField.font
                        leftPadding: 10
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: Qt.rgba(0.1, 0.04, 0.2, 0.95)
                        border.color: root.cfgSecondary
                        border.width: 1
                        radius: 6
                    }
                }

                Button {
                    id: loginButton
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 36
                    text: "log in"
                    font.family: root.cfgFont
                    font.pixelSize: 16
                    font.bold: true

                    contentItem: Text {
                        text: loginButton.text
                        color: "#F8F0FF"
                        font: loginButton.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: loginButton.pressed
                            ? Qt.darker(root.cfgPrimary, 1.3)
                            : (loginButton.hovered ? root.cfgPrimary : Qt.rgba(1.0, 0.18, 0.81, 0.85))
                        border.color: root.cfgAccent
                        border.width: 2
                        radius: 6

                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    onClicked: sddm.login(userField.currentText, passwordField.text, sessionField.currentIndex)
                }
            }

            Text {
                id: errorMessage
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignHCenter
                color: root.cfgNegative
                font.family: root.cfgMonoFont
                font.pixelSize: 14
                text: ""
                wrapMode: Text.WordWrap
            }
        }
    }

    // --- footer: hostname + clock ---
    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.left: parent.left
        anchors.leftMargin: 48
        text: sddm.hostName || "vibeos"
        color: root.cfgMuted
        font.family: root.cfgMonoFont
        font.pixelSize: 16
    }

    Text {
        id: clock
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 48
        color: root.cfgAccent
        font.family: root.cfgMonoFont
        font.pixelSize: 20

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                const d = new Date();
                const pad = n => n.toString().padStart(2, "0");
                clock.text = pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds());
            }
        }
    }

    // --- sddm signal bindings ---
    Connections {
        target: sddm
        function onLoginSucceeded() {
            errorMessage.text = "";
        }
        function onLoginFailed() {
            errorMessage.text = "login failed — try again";
            passwordField.selectAll();
            passwordField.forceActiveFocus();
        }
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}
