import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root
  property var host: null

  readonly property color fg: host ? host.contentForeground : Color.foreground
  readonly property string fontFamily: host ? host.contentFontFamily : Style.font.family
  readonly property var events: host ? host.selectedEvents : []
  readonly property var allDay: Model.allDayEvents(events)
  readonly property var timed: Model.timedEvents(events)
  readonly property var hours: Model.hourSlots()
  readonly property int hourHeight: Style.space(48)
  readonly property int labelWidth: Style.space(56)
  readonly property int nowMin: host ? (host.today.getHours() * 60 + host.today.getMinutes()) : 0
  readonly property bool isToday: host && host.selectedKey === host.todayKey

  Item {
    id: allDayBlock
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(Style.space(28), root.allDay.length * Style.space(24))

    Text {
      id: allDayLabel
      width: root.labelWidth
      anchors.verticalCenter: parent.verticalCenter
      text: "ALL-DAY"
      color: Qt.darker(root.fg, 1.7)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.8
    }

    Column {
      anchors.left: allDayLabel.right
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      spacing: Style.space(2)

      Repeater {
        model: root.allDay

        Rectangle {
          required property var modelData
          width: parent.width
          height: Style.space(22)
          color: root.host.eventColor(modelData)
          opacity: 0.22

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.space(3)
            color: root.host.eventColor(modelData)
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.title
            elide: Text.ElideRight
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.host.openEvent(modelData)
          }
        }
      }

      Text {
        visible: root.allDay.length === 0
        text: "No all-day events"
        color: Qt.darker(root.fg, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Flickable {
    id: flick
    anchors.top: allDayBlock.bottom
    anchors.topMargin: Style.space(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    contentWidth: width
    contentHeight: 24 * root.hourHeight
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: flick.scrollToFocus()

    function scrollToFocus() {
      var y = Math.max(0, (root.isToday ? root.nowMin : 8 * 60) / 60 * root.hourHeight - height / 3)
      contentY = Math.min(Math.max(0, y), Math.max(0, contentHeight - height))
    }

    Canvas {
      width: flick.width
      height: 24 * root.hourHeight
      renderTarget: Canvas.FramebufferObject
      onWidthChanged: paintWait.restart()
      onHeightChanged: paintWait.restart()
      Timer {
        id: paintWait
        interval: 16
        onTriggered: parent.requestPaint()
      }
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = Qt.darker(root.fg, 1.7).toString()
        ctx.strokeStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10).toString()
        ctx.font = Style.font.caption + "px sans-serif"
        ctx.textBaseline = "middle"
        ctx.lineWidth = 1
        var hours = root.hours
        for (var i = 0; i < hours.length; i++) {
          var y = hours[i].hour * root.hourHeight
          ctx.beginPath()
          ctx.moveTo(root.labelWidth, y + 0.5)
          ctx.lineTo(width, y + 0.5)
          ctx.stroke()
          if (hours[i].label)
            ctx.fillText(hours[i].label, 0, y)
        }
      }
    }

    Repeater {
      model: root.timed

      Rectangle {
        required property var modelData
        readonly property var place: Model.eventPlacement(modelData)
        x: root.labelWidth + Style.space(6)
        width: flick.width - x - Style.space(8)
        y: place.startMin / 60 * root.hourHeight
        height: Math.max(Style.space(22), (place.endMin - place.startMin) / 60 * root.hourHeight - 2)
        color: Qt.rgba(root.host.eventColor(modelData).r, root.host.eventColor(modelData).g, root.host.eventColor(modelData).b, 0.22)

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(3)
          color: root.host.eventColor(modelData)
        }

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(6)
          anchors.topMargin: Style.space(4)
          text: (modelData.start ? modelData.start + "  " : "") + modelData.title
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.host.openEvent(modelData)
        }
      }
    }

    Rectangle {
      visible: root.isToday
      x: root.labelWidth
      width: flick.width - x
      y: root.nowMin / 60 * root.hourHeight
      height: Style.spacing.hairline
      color: Color.accent
    }
  }
}
