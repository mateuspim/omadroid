import QtQuick

// Offscreen stand-in for qs.Ui's KeyboardPanel: without a compositor there is
// no PanelWindow backend, so previews mount the popup content in a plain Item.
Item {
  property Item anchorItem
  property QtObject bar
  property var owner: null
  property int contentWidth: 428
  property int contentHeight: 600
  property bool open: false
  property Item focusTarget: null
  default property alias contentItem: holder.children
  function fittedContentWidth(width, cap) {
    return width;
  }
  function fittedContentHeight(height, cap) {
    return cap ? Math.min(height, cap) : height;
  }
  Item {
    id: holder
    width: 428
    height: 860
  }
}
