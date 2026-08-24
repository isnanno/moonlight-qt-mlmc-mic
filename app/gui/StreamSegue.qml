import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Window 2.2

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import StreamingPreferences 1.0

Item {
    property Session session
    property var appModel
    property int appIndex: -1
    property string appName
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false
    property bool pendingReconnect: false
    property bool sessionCleanupDone: false

    function bindSession(newSession)
    {
        newSession.stageStarting.connect(stageStarting)
        newSession.stageFailed.connect(stageFailed)
        newSession.connectionStarted.connect(connectionStarted)
        newSession.displayLaunchError.connect(displayLaunchError)
        newSession.displayLaunchWarning.connect(displayLaunchWarning)
        newSession.quitStarting.connect(quitStarting)
        newSession.sessionFinished.connect(sessionFinished)
        newSession.readyForDeletion.connect(sessionReadyForDeletion)
    }

    function startStream()
    {
        hintText.text = qsTr("Tip:") + " " + qsTr("Press %1 to disconnect your session").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ?
                                              qsTr("Start+Select+L1+R1") : qsTr("Ctrl+Alt+Shift+Q"))

        SdlGamepadKeyNavigation.disable()
        gc()
        session.exec(Window.window)
    }

    function tryReconnectAfterDelay()
    {
        if (!pendingReconnect || !sessionCleanupDone || reconnectTimer.running) {
            return
        }

        doReconnect()
    }

    function shouldAutoReconnect()
    {
        return StreamingPreferences.autoReconnectOnError &&
               session !== null &&
               session.terminationErrorCode === -1 &&
               !quitAfter &&
               appModel !== null &&
               appIndex >= 0
    }

    function doReconnect()
    {
        pendingReconnect = false
        sessionCleanupDone = false
        streamSegueErrorDialog.text = ""

        stageText = isResume ? qsTr("Resuming %1...").arg(appName) :
                               qsTr("Starting %1...").arg(appName)
        stageSpinner.visible = true
        stageLabel.visible = true
        stageSpinner.running = true
        hintText.visible = true
        window.visible = false

        session = appModel.createSessionForApp(appIndex)
        bindSession(session)
        startStream()
    }

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)

        if (failingPorts) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function connectionStarted()
    {
        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        stageSpinner.visible = false
        stageLabel.visible = false
        hintText.visible = false

        // Hide the window now that streaming has begun
        window.visible = false
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = text
        console.error(text)
    }

    function displayLaunchWarning(text)
    {
        // This toast appears for 3 seconds, just shorter than how long
        // Session will wait for it to be displayed. This gives it time
        // to transition to invisible before continuing.
        var toast = Qt.createQmlObject('import QtQuick.Controls 2.2; ToolTip {}', parent, '')
        toast.text = text
        toast.timeout = 3000
        toast.visible = true
        console.warn(text)
    }

    function quitStarting()
    {
        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.replace(stackView.currentItem, component.createObject(stackView, {"appName": appName}), StackView.Immediate)

        // Show the Qt window again to show quit segue
        window.visible = true
    }

    function sessionFinished(portTestResult)
    {
        if (shouldAutoReconnect()) {
            pendingReconnect = true
            sessionCleanupDone = false
            streamSegueErrorDialog.text = ""
            stageText = qsTr("Connection lost. Reconnecting in 1 second...")
            stageSpinner.visible = true
            stageLabel.visible = true
            stageSpinner.running = true
            reconnectTimer.start()
            return
        }

        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
        }

        // Enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        if (quitAfter) {
            if (streamSegueErrorDialog.text) {
                // Quit when the error dialog is acknowledged
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
            else {
                // Quit immediately
                Qt.quit()
            }
        } else {
            // Exit this view
            stackView.pop()

            // Show the Qt window again after streaming
            window.visible = true

            // Display any launch errors. We do this after
            // the Qt UI is visible again to prevent losing
            // focus on the dialog which would impact gamepad
            // users.
            if (streamSegueErrorDialog.text) {
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
        }
    }

    function sessionReadyForDeletion()
    {
        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        session = null
        gc()
        sessionCleanupDone = true
        tryReconnectAfterDelay()
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack
        toolBar.visible = true

        // Enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading
        toolBar.visible = false

        bindSession(session)

        // Kick off the stream
        spinnerTimer.start()
        streamLoader.active = true
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        onTriggered: tryReconnectAfterDelay()
    }

    Timer {
        id: spinnerTimer

        // Display the spinner appearance a bit to allow us to reach
        // the code in Session.exec() that pumps the event loop.
        // If we display it immediately, it will briefly hang in the
        // middle of the animation on Windows, which looks very
        // obviously broken.
        interval: 100
        onTriggered: stageSpinner.running = true
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            startStream()
        }

        sourceComponent: Item {}
    }

    Row {
        anchors.centerIn: parent
        spacing: 5

        BusyIndicator {
            id: stageSpinner
            running: false
        }

        Label {
            id: stageLabel
            height: stageSpinner.height
            text: stageText
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.Wrap
        }
    }

    Label {
        id: hintText
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        font.pointSize: 18
        verticalAlignment: Text.AlignVCenter

        wrapMode: Text.Wrap
    }
}
