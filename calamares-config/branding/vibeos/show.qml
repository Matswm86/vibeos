// VibeOS Calamares install slideshow — Pacific Dawn, hosted by Vibbey.
// Five slides, each with the canonical Vibbey image and high-contrast
// cream text on a deep ink-purple "night sky" backdrop. (Earlier
// dawn-gradient lost cream text against the cream lower portion.)

import QtQuick 2.15
import QtQuick.Controls 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        id: advanceTimer
        interval:  9000
        running:   presentation.activatedInCalamares
        repeat:    true
        onTriggered: presentation.goToNextSlide()
    }

    component NightBg: Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#1C102E" }
            GradientStop { position: 0.55; color: "#3C2352" }
            GradientStop { position: 1.00; color: "#2D1B3E" }
        }
    }

    component Vibbey: Image {
        source: "vibbey-mascot.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        width: 220; height: 220
    }

    component Title: Text {
        color: "#FFF4E6"
        font.family: "Orbitron"
        font.pixelSize: 36
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    component Body: Text {
        color: "#FFC79E"
        font.family: "JetBrains Mono"
        font.pixelSize: 18
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    component Hint: Text {
        color: "#FF8FB8"
        font.family: "JetBrains Mono"
        font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Slide {
        NightBg {}
        Column {
            anchors.centerIn: parent
            spacing: 16
            Vibbey { anchors.horizontalCenter: parent.horizontalCenter }
            Title  { text: "Welcome to VibeOS" ; anchors.horizontalCenter: parent.horizontalCenter }
            Body   {
                text: "Pacific Dawn — your AI-native desktop.\nVibbey will keep you company while we install."
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Hint   {
                text: "Hit Enter at the login prompt — no password needed on the live session."
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Slide {
        NightBg {}
        Column {
            anchors.centerIn: parent
            spacing: 16
            Vibbey { anchors.horizontalCenter: parent.horizontalCenter }
            Title  { text: "Meet Vibbey" ; anchors.horizontalCenter: parent.horizontalCenter }
            Body   {
                text: "Your local AI sidekick — runs on-device with Ollama.\nPrivacy-safe, no cloud round-trip, always available."
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Slide {
        NightBg {}
        Column {
            anchors.centerIn: parent
            spacing: 16
            Vibbey { anchors.horizontalCenter: parent.horizontalCenter }
            Title  { text: "Claude Code, baked in" ; anchors.horizontalCenter: parent.horizontalCenter }
            Body   {
                text: "Open a terminal, type `claude`, ship code.\nAnthropic's coding agent, ready out of the box."
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Slide {
        NightBg {}
        Column {
            anchors.centerIn: parent
            spacing: 16
            Vibbey { anchors.horizontalCenter: parent.horizontalCenter }
            Title  { text: "Yours, locally" ; anchors.horizontalCenter: parent.horizontalCenter }
            Body   {
                text: "No telemetry. No accounts required.\nYour memory graph and notes never leave the box\nunless you ask Vibbey to share."
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Slide {
        NightBg {}
        Column {
            anchors.centerIn: parent
            spacing: 16
            Vibbey { anchors.horizontalCenter: parent.horizontalCenter }
            Title  { text: "Almost there" ; anchors.horizontalCenter: parent.horizontalCenter }
            Body   {
                text: "When the install finishes, sign in and\nVibbey will say hi on first boot.\nWelcome to the dawn."
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    function onActivate() { advanceTimer.running = true }
    function onLeave()    { advanceTimer.running = false }
}
