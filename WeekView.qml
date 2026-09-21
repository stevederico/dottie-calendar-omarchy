import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root
  property var host: null

  readonly property color fg: host ? host.contentForeground : Color.foreground
  readonly property string fontFamily: host ? host.contentFontFamily : Style.font.family
  readonly property var days: host ? host.weekDays : []
  readonly property var hours: Model.hourSlots()
  readonly property int hourHeight: Style.space(44)
  readonly property int labelWidth: Style.space(56)
  readonly property int colWidth: Math.max(Style.space(80), Math.floor((width - labelWidth) / 7))
  readonly property int nowMin: host ? (host.today.getHours() * 60 + host.today.getMinutes()) : 0

  Row {
    id: weekHeader
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(44)
    spacing: 0

    Item {
      width: root.labelWidth
      height: parent.height
    }

    Repeater {
      model: root.days

      Item {
        required property var modelData
        width: root.colWidth
        height: parent.height

        Text {
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.host.weekdayLabel(modelData.weekday)
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          font.bold: true
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          text: modelData.day
          color: modelData.today || (root.host && modelData.key === root.host.selectedKey)
            ? root.fg
            : Qt.darker(root.fg, modelData.weekend ? 1.45 : 1.15)
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: modelData.today || (root.host && modelData.key === root.host.selectedKey)
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: false
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.host.selectDay(modelData)
            root.host.viewMode = "day"
          }
        }
      }
    }
  }

  Row {
    id: allDayRow
    anchors.top: weekHeader.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(28)
    spacing: 0

    Item {
      width: root.labelWidth
      height: parent.height
    }

    Repeater {
      model: root.days

      Item {
        required property var modelData
        readonly property var allDay: Model.allDayEvents(root.host.dayEvents(modelData.key))
        width: root.colWidth
        height: parent.height
        clip: true

        Repeater {
          model: parent.allDay

          Rectangle {
            required property var modelData
            required property int index
            x: Style.space(2)
            y: index * (Style.space(12) + 1)
            width: parent.width - Style.space(4)
            height: Style.space(12)
            color: Qt.rgba(root.host.eventColor(modelData).r, root.host.eventColor(modelData).g, root.host.eventColor(modelData).b, 0.22)

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.space(4)
              text: modelData.title
              elide: Text.ElideRight
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Math.max(10, Style.font.caption - 1)
              verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.host.openEvent(modelData)
            }
          }
        }
      }
    }
  }

  Flickable {
    id: flick
    anchors.top: allDayRow.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    contentWidth: width
    contentHeight: 24 * root.hourHeight
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: {
      var y = Math.max(0, 8 * root.hourHeight - height / 4)
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
      model: root.days

      Item {
        required property var modelData
        required property int index
        readonly property var timed: Model.timedEvents(root.host.dayEvents(modelData.key))
        x: root.labelWidth + index * root.colWidth
        width: root.colWidth
        height: 24 * root.hourHeight

        Rectangle {
          anchors.fill: parent
          color: root.host && modelData.key === root.host.selectedKey
            ? Style.hoverFillFor(root.fg, Color.accent)
            : "transparent"
        }

        Repeater {
          model: parent.timed

          Rectangle {
            required property var modelData
            readonly property var place: Model.eventPlacement(modelData)
            x: Style.space(2)
            width: parent.width - Style.space(4)
            y: place.startMin / 60 * root.hourHeight
            height: Math.max(Style.space(18), (place.endMin - place.startMin) / 60 * root.hourHeight - 2)
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
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(4)
              anchors.topMargin: Style.space(2)
              text: modelData.title
              elide: Text.ElideRight
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Math.max(10, Style.font.caption)
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.host.openEvent(modelData)
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: false
          z: -1
          onClicked: root.host.selectDay(modelData)
        }

        Rectangle {
          visible: modelData.today
          x: 0
          width: parent.width
          y: root.nowMin / 60 * root.hourHeight
          height: Style.spacing.hairline
          color: Color.accent
        }
      }
    }
  }
}
