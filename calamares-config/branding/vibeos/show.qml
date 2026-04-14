// VibeOS Calamares install slideshow — minimal Pacific Dawn placeholder.
// Day 2 ships the three-slide stub below. Real Vibbey-narrated animation
// lands in a later sprint (not blocking v2.0.0).

import QtQuick 2.15
import QtQuick.Controls 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        id: advanceTimer
        interval:  8000
        running:   presentation.activatedInCalamares
        repeat:    true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#FFF4E6"

            Column {
                anchors.centerIn: parent
                spacing: 24

                Text {
                    text: "Welcome to VibeOS"
                    color: "#2D1B3E"
                    font.family: "Orbitron"
                    font.pixelSize: 48
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Pacific Dawn — your AI-native desktop"
                    color: "#FF5A8F"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 22
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#FFF4E6"
            Text {
                anchors.centerIn: parent
                text: "Vibbey — your local AI, always on,\nprivacy-safe, zero cloud round-trip."
                color: "#2D1B3E"
                font.family: "Orbitron"
                font.pixelSize: 28
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#FFF4E6"
            Text {
                anchors.centerIn: parent
                text: "Claude Code, baked in.\nOpen a terminal. Say hi. Ship code."
                color: "#FF7A00"
                font.family: "Orbitron"
                font.pixelSize: 28
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    function onActivate() {
        advanceTimer.running = true
    }
    function onLeave() {
        advanceTimer.running = false
    }
}
