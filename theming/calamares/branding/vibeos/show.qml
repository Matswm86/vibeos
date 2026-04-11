/*
 * VibeOS Calamares slideshow — slideshowAPI: 2
 *
 * Five panels that cycle while the install runs. Pure QML, no images
 * required beyond branding.images.productLogo. Background is the same
 * deep purple as the rest of the installer so there's no jarring
 * white-flash between pages.
 */
import QtQuick 2.5
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        interval:    8000
        running:     presentation.activatedInCalamares
        repeat:      true
        onTriggered: presentation.goToNextSlide()
    }

    // ── Slide 1 — Welcome ─────────────────────────────────────
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0B0218"

            Column {
                anchors.centerIn: parent
                spacing: 18

                Image {
                    source: "vibeos-logo.png"
                    width:  140
                    height: 140
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "Welcome to VibeOS"
                    color: "#01F9FF"
                    font.pixelSize: 32
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "An opinionated AI-dev workstation"
                    color: "#F8F0FF"
                    font.pixelSize: 16
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ── Slide 2 — What's included ─────────────────────────────
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0B0218"

            Column {
                anchors.centerIn: parent
                spacing: 14
                width: parent.width * 0.8

                Text {
                    text: "Out of the box"
                    color: "#FF2ECF"
                    font.pixelSize: 28
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "• Claude Code  • Ollama  • Docker\n• Node.js  • Python  • GitHub CLI\n• KDE Plasma with VibeOS-Neon theme"
                    color: "#F8F0FF"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ── Slide 3 — Vibbey ─────────────────────────────────────
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0B0218"

            Column {
                anchors.centerIn: parent
                spacing: 14
                width: parent.width * 0.8

                Text {
                    text: "Meet Vibbey"
                    color: "#01F9FF"
                    font.pixelSize: 28
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "Your desktop assistant launches on first login.\nAsk anything — Vibbey routes to local Ollama\nor Groq when you want speed."
                    color: "#F8F0FF"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ── Slide 4 — Free & open ─────────────────────────────────
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0B0218"

            Column {
                anchors.centerIn: parent
                spacing: 14
                width: parent.width * 0.8

                Text {
                    text: "Free, forever"
                    color: "#FF2ECF"
                    font.pixelSize: 28
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "VibeOS is free and open-source.\nNo accounts, no telemetry, no upsell.\ngithub.com/Matswm86/vibeos"
                    color: "#F8F0FF"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ── Slide 5 — Almost ready ────────────────────────────────
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0B0218"

            Column {
                anchors.centerIn: parent
                spacing: 14

                Text {
                    text: "Hang tight…"
                    color: "#01F9FF"
                    font.pixelSize: 32
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "VibeOS is being installed."
                    color: "#F8F0FF"
                    font.pixelSize: 16
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ── Slideshow lifecycle hooks (slideshowAPI 2) ────────────
    function onActivate()   { /* nothing */ }
    function onLeave()      { /* nothing */ }
}
