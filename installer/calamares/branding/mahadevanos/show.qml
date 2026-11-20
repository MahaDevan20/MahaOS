// Calamares slideshow for MahaDevan's OS (slideshowAPI 2).
// Keep it dependency-free: only QtQuick primitives, no external modules.
import QtQuick 2.15

Rectangle {
    id: root
    color: "#101820"

    property int idx: 0
    property var slides: [
        {
            "title": "Welcome to MahaDevan's OS",
            "text": "An Arch-based system with a Garuda-style offline install. Nothing is downloaded while installing."
        },
        {
            "title": "Your filesystem",
            "text": "Btrfs with zstd compression and separate subvolumes for /, /home, logs, cache and snapshots."
        },
        {
            "title": "Updates you can undo",
            "text": "snapper and snap-pac snapshot every package transaction. If an update breaks, boot the previous snapshot from the GRUB menu."
        },
        {
            "title": "Drivers included",
            "text": "Mesa, Vulkan for AMD and Intel, full linux-firmware, microcode and SOF audio firmware are already inside the ISO."
        },
        {
            "title": "Almost there",
            "text": "The installer is copying the live system image to your disk. This takes a few minutes and needs no internet."
        }
    ]

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 24

        Text {
            width: parent.width
            text: root.slides[root.idx].title
            color: "#23ebd1"
            font.pixelSize: 34
            font.bold: true
            wrapMode: Text.WordWrap
        }
        Text {
            width: parent.width
            text: root.slides[root.idx].text
            color: "#e6edf3"
            font.pixelSize: 20
            wrapMode: Text.WordWrap
            lineHeight: 1.3
        }
        Text {
            text: "MahaDevan's OS 0.1"
            color: "#6b7d8f"
            font.pixelSize: 16
        }
    }

    Timer {
        interval: 7000
        running: true
        repeat: true
        onTriggered: root.idx = (root.idx + 1) % root.slides.length
    }
}
