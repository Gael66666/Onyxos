import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0B0A10"

    Image {
        anchors.fill: parent
        source: "sddm-background.png"
        fillMode: Image.PreserveAspectCrop
        opacity: 0.92
    }

    Rectangle {
        anchors.fill: parent
        color: "#0B0A10"
        opacity: 0.28
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: 380
        spacing: 18

        Image {
            source: "../../../../pixmaps/onyxos-logo.png"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 116
            Layout.preferredHeight: 116
            fillMode: Image.PreserveAspectFit
        }

        Label {
            text: "ONYXOS"
            color: "#EDE9FE"
            font.pixelSize: 28
            font.bold: true
            font.letterSpacing: 5
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: "Plasma Edition"
            color: "#C084FC"
            font.pixelSize: 14
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: form.implicitHeight + 42
            color: "#151320"
            opacity: 0.94
            radius: 16
            border.color: "#8B5CF6"
            border.width: 1

            ColumnLayout {
                id: form
                anchors.fill: parent
                anchors.margins: 21
                spacing: 12

                ComboBox {
                    id: userBox
                    Layout.fillWidth: true
                    model: userModel
                    textRole: "name"
                    valueRole: "name"
                }

                TextField {
                    id: password
                    Layout.fillWidth: true
                    placeholderText: "Mot de passe"
                    echoMode: TextInput.Password
                    selectByMouse: true
                    onAccepted: loginButton.clicked()
                }

                Button {
                    id: loginButton
                    text: "Ouvrir la session"
                    Layout.fillWidth: true
                    onClicked: sddm.login(userBox.currentText, password.text, sessionModel.lastIndex)
                }
            }
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() { password.text = ""; password.forceActiveFocus() }
    }

    Component.onCompleted: password.forceActiveFocus()
}
