
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:glib/core/array.dart';
import 'package:glib/core/callback.dart';
import 'package:glib/core/gmap.dart';
import 'package:glib/main/context.dart';
import 'package:glib/main/data_item.dart';
import 'package:glib/main/models.dart';
import 'package:kinoko/configs.dart';
import 'package:kinoko/widgets/pager/horizontal_pager.dart';
import 'package:kinoko/widgets/pager/webtoon_pager.dart';
import 'package:kinoko/widgets/picture_hint_painter.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:glib/main/error.dart' as glib;
import 'package:glib/utils/bit64.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:quds_popup_menu/quds_popup_menu.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'main.dart';
import 'utils/download_manager.dart';
import 'utils/neo_cache_manager.dart';
import 'utils/preload_queue.dart';
import 'dart:math' as math;
import 'localizations/localizations.dart';
import 'widgets/instructions_dialog.dart';
import 'widgets/page_slider.dart';
import 'widgets/pager/pager.dart';
import 'utils/data_item_headers.dart';
import 'dart:ui' as ui;
import 'utils/fullscreen.dart';
import 'widgets/pager/vertical_pager.dart';

enum PictureFlipType {
  Next,
  Prev
}

class HorizontalIconPainter extends CustomPainter {

  final Color textColor;

  HorizontalIconPainter(this.textColor);

  @override
  void paint(Canvas canvas, Size size) {
    drawIcon(canvas, Icons.border_vertical, Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.translate(size.width, 0);
    canvas.scale(-1, 1);
    double inset = size.width * 0.05;
    drawIcon(canvas, Icons.arrow_right_alt_sharp, Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2));
  }

  void drawIcon(Canvas canvas, IconData icon, Rect rect) {
    var builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: icon.fontFamily,
    ))
      ..pushStyle(ui.TextStyle(
        color: textColor,
        fontSize: rect.width
      ))
      ..addText(String.fromCharCode(icon.codePoint));
    var para = builder.build();
    para.layout(ui.ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(para, Offset(rect.left, rect.top));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is HorizontalIconPainter) {
      return oldDelegate.textColor != textColor;
    } else {
      return true;
    }
  }
}

class PictureViewer extends StatefulWidget {
  final Context context;
  final Context Function(PictureFlipType) onChapterChanged;
  final int startPage;
  final void Function(DataItem) onDownload;

  PictureViewer(this.context, {
    this.onChapterChanged,
    this.onDownload,
    this.startPage,
  });

  @override
  State<StatefulWidget> createState() {
    return _PictureViewerState();
  }
}

enum FlipType {
  Horizontal,
  HorizontalReverse,
  RightToLeft,
  Vertical,
  Webtoon,
}

HintMatrix _hintMatrix(FlipType type) {
  switch (type) {
    case FlipType.Horizontal: {
      return HintMatrix([
        -1, 0, 1,
        -1, 0, 1,
        -1, 0, 1,
      ]);
    }
    case FlipType.HorizontalReverse: {
      return HintMatrix();
    }
    case FlipType.RightToLeft: {
      return HintMatrix([
        1, 0, -1,
        1, 0, -1,
        1, 0, -1,
      ]);
    }
    case FlipType.Vertical:
    case FlipType.Webtoon:
      {
      return HintMatrix([
        -1, -1, -1,
        -1,  0,  1,
         1,  1,  1,
      ]);
    }
    default: {
      throw Exception("Unkown type $type");
    }
  }
}

class _PictureViewerState extends State<PictureViewer> {

  Array data;
  int index = 0;
  int touchState = 0;
  bool appBarDisplay = true;
  MethodChannel channel;
  String cacheKey;
  PreloadQueue preloadQueue;
  bool loading = false;
  Timer _timer;
  NeoCacheManager _cacheManager;
  PagerController pagerController;
  FlipType flipType = FlipType.Horizontal;
  bool isLandscape = false;

  GlobalKey iconKey = GlobalKey();

  String _directionKey;
  String _deviceKey;
  String _pageKey;
  bool _firstTime = true;
  bool _hintDisplay = false;

  GlobalKey<PageSliderState> _sliderKey = GlobalKey();

  Context pictureContext;
  GlobalKey _canvasKey = GlobalKey();

  void onDataChanged(int type, Array data, int pos) {
    if (data != null) {
      addToPreload(data);
      setState(() {});
    }
  }

  void onLoadingStatus(bool isLoading) {
    setState(() {
      loading = isLoading;
    });
  }

  void onError(glib.Error error) {
    Fluttertoast.showToast(
      msg: error.msg,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  void pageNext() {
    pagerController.next();
  }

  void pagePrev() {
    pagerController.prev();
  }

  Future<void> onVolumeButtonClicked(MethodCall call) async {
    if (call.method == "keyDown") {
      int code = call.arguments;
      switch (code) {
        case 1: {
          pageNext();
          break;
        }
        case 2: {
          pagePrev();
          break;
        }
      }
    }
  }

  NeoCacheManager get cacheManager {
    if (_cacheManager == null) {
      // DataItem item = widget.context.infoData;
      _cacheManager = NeoCacheManager(cacheKey);
    }
    return _cacheManager;
  }

  void setAppBarDisplay(display) {
    setState(() {
      appBarDisplay = display;
      // SystemChrome.setEnabledSystemUIOverlays(display ? SystemUiOverlay.values : []);
      if (display) {
        exitFullscreen();
      } else {
        enterFullscreen();
        _sliderKey.currentState?.dismiss();
        _hintTimer?.cancel();
        _hintDisplay = false;
      }
    });

  }

  void onTapScreen() {
    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
    setAppBarDisplay(!appBarDisplay);
  }

  Widget buildPager(BuildContext context) {
    if (_firstTime && widget.startPage != null) {
      pagerController.index = math.max(math.min(widget.startPage, data.length - 1), 0);
      index = pagerController.index;
      preloadQueue.offset = index;
    }
    _firstTime = false;
    switch (flipType) {
      case FlipType.Horizontal:
      case FlipType.HorizontalReverse: {
        return HorizontalPager(
          key: ValueKey(pagerController),
          reverse: flipType == FlipType.HorizontalReverse,
          cacheManager: cacheManager,
          controller: pagerController,
          itemCount: data.length,
          imageUrlProvider: (int index) {
            DataItem item = (data[index] as DataItem);
            return PhotoInformation(item.picture, item.headers);
          },
          onTap: (event) {
            tapAt(event.position);
          },
        );
      }
      case FlipType.RightToLeft: {
        return HorizontalPager(
          key: ValueKey(pagerController),
          cacheManager: cacheManager,
          controller: pagerController,
          itemCount: data.length,
          imageUrlProvider: (int index) {
            DataItem item = (data[index] as DataItem);
            return PhotoInformation(item.picture, item.headers);
          },
          onTap: (event) {
            tapAt(event.position);
          },
          direction: AxisDirection.left,
        );
      }
      case FlipType.Vertical: {
        return VerticalPager(
          key: ValueKey(pagerController),
          cacheManager: cacheManager,
          controller: pagerController,
          itemCount: data.length,
          imageUrlProvider: (int index) {
            DataItem item = (data[index] as DataItem);
            return PhotoInformation(item.picture, item.headers);
          },
          onTap: (event) {
            tapAt(event.position);
          },
        );
      }
      case FlipType.Webtoon: {
        return WebtoonPager(
          key: ValueKey(pagerController),
          cacheManager: cacheManager,
          controller: pagerController,
          itemCount: data.length,
          imageUrlProvider: (int index) {
            DataItem item = (data[index] as DataItem);
            return PhotoInformation(item.picture, item.headers);
          },
          onTap: (event) {
            tapAt(event.position);
          },
        );
      }
      default: {
        return Container();
      }
    }
  }

  void showPagePicker() {
    if (!appBarDisplay) {
      setAppBarDisplay(true);
      return;
    }

    _sliderKey.currentState?.show();
  }

  @override
  Widget build(BuildContext context) {
    double size = IconTheme.of(context).size;

    List<QudsPopupMenuBase> menuItems = [
      QudsPopupMenuSection(
          titleText: kt("page_mode"),
          leading: Icon(
            Icons.flip,
          ),
          subItems: [
            QudsPopupMenuItem(
                leading: Icon(Icons.border_vertical),
                title: Text(kt("horizontal_flip")),
                trailing: flipType == FlipType.Horizontal ?
                Icon(Icons.check) : null,
                onPressed: flipType == FlipType.Horizontal ? null : () {
                  if (flipType != FlipType.Horizontal) {
                    setState(() {
                      flipType = FlipType.Horizontal;
                    });
                    displayHint();
                    KeyValue.set(_directionKey, "horizontal");
                  }
                },
            ),
            QudsPopupMenuItem(
                leading: Container(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: HorizontalIconPainter(Colors.black87),
                    size: Size(size, size),
                  ),
                ),
                title: Text(kt("horizontal_reverse")),
                trailing: flipType == FlipType.HorizontalReverse ?
                Icon(Icons.check) : null,
                onPressed: flipType == FlipType.HorizontalReverse ? null : () {
                  if (flipType != FlipType.HorizontalReverse) {
                    setState(() {
                      flipType = FlipType.HorizontalReverse;
                    });
                    displayHint();
                    KeyValue.set(_directionKey, "horizontal_reverse");
                  }
                },
            ),
            QudsPopupMenuItem(
              leading: Transform.rotate(
                angle: math.pi,
                child: Icon(Icons.arrow_right_alt),
                alignment: Alignment.center,
              ),
              title: Text(kt("right_to_left")),
              trailing: flipType == FlipType.RightToLeft ?
              Icon(Icons.check) : null,
              onPressed: flipType == FlipType.RightToLeft ? null : () {
                if (flipType != FlipType.RightToLeft) {
                  setState(() {
                    flipType = FlipType.RightToLeft;
                  });
                  displayHint();
                  KeyValue.set(_directionKey, "right_to_left");
                }
              },
            ),
            QudsPopupMenuItem(
                leading: Icon(Icons.border_horizontal),
                title: Text(kt('vertical_flip')),
                trailing: flipType == FlipType.Vertical ?
                Icon(Icons.check) : null,
                onPressed: () {
                  if (flipType != FlipType.Vertical) {
                    setState(() {
                      flipType = FlipType.Vertical;
                    });
                    displayHint();
                    KeyValue.set(_directionKey, "vertical");
                  }
                },
            ),

            QudsPopupMenuItem(
              leading: Icon(Icons.web_asset_sharp),
              title: Text(kt('webtoon')),
              trailing: flipType == FlipType.Webtoon ?
              Icon(Icons.check) : null,
              onPressed: () {
                if (flipType != FlipType.Webtoon) {
                  setState(() {
                    flipType = FlipType.Webtoon;
                  });
                  displayHint();
                  KeyValue.set(_directionKey, "webtoon");
                }
              },
            ),
          ]
      ),
      QudsPopupMenuSection(
          leading: isLandscape ? Icon(Icons.stay_current_landscape) : Icon(Icons.stay_current_portrait),
          titleText: kt('orientation'),
          subItems: [
            QudsPopupMenuItem(
                leading: Icon(Icons.stay_current_portrait),
                title: Text(kt("portrait")),
                trailing: !isLandscape ?
                Icon(Icons.check) : null,
                onPressed: !isLandscape ? null : () {
                  if (isLandscape) {
                    setState(() {
                      isLandscape = false;
                      updateOrientation();
                    });
                    KeyValue.set(_deviceKey, "portrait");
                  }
                }
            ),
            QudsPopupMenuItem(
                leading: Icon(Icons.stay_current_landscape),
                title: Text(kt("landscape")),
                trailing: isLandscape ?
                Icon(Icons.check) : null,
                onPressed: isLandscape ? null : () {
                  if (!isLandscape) {
                    setState(() {
                      isLandscape = true;
                      updateOrientation();
                    });
                    KeyValue.set(_deviceKey, "landscape");
                  }
                }
            ),
          ]
      ),
    ];
    if (widget.onDownload != null) {
      menuItems.add(QudsPopupMenuItem(
          leading: Icon(Icons.file_download),
          title: Text(kt('download')),
          onPressed: () {
            widget.onDownload(pictureContext.infoData);
            Fluttertoast.showToast(msg: kt('added_download').replaceAll('{0}', "1"));
          }
      ),);
    }
    menuItems.add(QudsPopupMenuItem(
        leading: Icon(
          Icons.help_outline,
          key: iconKey,
        ),
        title: Text(kt("instructions")),
        onPressed: () {
          showInstructionsDialog(context, 'assets/picture',
            entry: kt('lang'),
            iconColor: Theme.of(context).primaryColor,
          );
        }
    ),);

    var padding = MediaQuery.of(context).padding;

    return AnnotatedRegion<SystemUiOverlayStyle>(
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.black,
          body: Stack(
            children: <Widget>[
              GestureDetector(
                key: _canvasKey,
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: data.length == 0 ?
                        Center(
                          child: SpinKitRing(
                            lineWidth: 4,
                            size: 36,
                            color: Colors.white,
                          ),
                        ):
                        buildPager(context),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _hintDisplay ? 1 : 0,
                            duration: Duration(
                              milliseconds: 300,
                            ),
                            child: CustomPaint(
                              painter: PictureHintPainter(
                                matrix: _hintMatrix(flipType),
                                prevText: kt("prev"),
                                menuText: kt("menu"),
                                nextText: kt("next")
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ),
                onTapUp: (event) {
                  tapAt(event.localPosition);
                },
              ),

              AnimatedPositioned(
                child: Container(
                  color: Colors.black26,
                  child: Row(
                    children: <Widget>[
                      IconButton(
                          icon: Icon(Icons.arrow_back),
                          color: Colors.white,
                          onPressed: () {
                            Navigator.of(context).pop();
                          }
                      ),
                      Expanded(
                          child: Text(
                            pictureContext.infoData.title,
                            style: Theme.of(context).textTheme.headline6.copyWith(color: Colors.white),
                          )
                      ),
                      QudsPopupButton(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: 10,
                          ),
                          child: Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                        ),
                        items: menuItems,
                      ),
                    ],
                  ),
                ),
                top: appBarDisplay ? padding.top : (-44),
                left: padding.left,
                right: padding.right,
                height: 44,
                duration: Duration(milliseconds: 300),
              ),

              Positioned(
                child: AnimatedOpacity(
                    child: TextButton(
                      onPressed: showPagePicker,
                      child: Text.rich(
                        TextSpan(
                            children: [
                              WidgetSpan(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(Icons.toc, color: Colors.white,size: 16,),
                                  ),
                                  alignment: PlaceholderAlignment.middle
                              ),
                              TextSpan(
                                text: data.length > 0 ? "${index == -1 ? data.length : (index + 1)}/${data.length}" : "",
                                style: Theme.of(context).textTheme.bodyText1.copyWith(color: Colors.white),
                              ),
                              WidgetSpan(child: Container(padding: EdgeInsets.only(left: 5),)),
                              WidgetSpan(
                                  child: AnimatedOpacity(
                                    opacity: loading ? 1 : 0,
                                    duration: Duration(milliseconds: 300),
                                    child: SpinKitFoldingCube(
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                  alignment: PlaceholderAlignment.middle
                              )
                            ]
                        ),
                        style: TextStyle(
                            shadows: [
                              Shadow(
                                  color: Colors.black26,
                                  blurRadius: 2,
                                  offset: Offset(1, 1)
                              )
                            ]
                        ),
                      ),
                    ),
                    opacity: appBarDisplay ? 1 : 0,
                    duration: Duration(milliseconds: 300)
                ),
                right: 10 + padding.right,
                bottom: 0,
              ),

              Positioned(
                child: index == -1 ? Container() : PageSlider(
                  key: _sliderKey,
                  total: data.length,
                  page: index,
                  onPage: (page) {
                    setState(() {
                      index = page;
                    });
                    return pagerController.animateTo(page);
                  },
                  onAppear: () {
                    _timer?.cancel();
                    _timer = null;
                  },
                ),
                right: 26 + padding.right,
                bottom: 6,
                left: 10 + padding.left,
                height: 40,
              ),
            ],
          ),
        ),
        value: SystemUiOverlayStyle.dark.copyWith(
          systemNavigationBarDividerColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          statusBarColor: Colors.black26,
        ),
    );
  }

  void touch() {
    cacheKey = NeoCacheManager.cacheKey(pictureContext.infoData);
    _cacheManager = NeoCacheManager(cacheKey);
    preloadQueue = PreloadQueue();
    pictureContext.control();
    pictureContext.onDataChanged = Callback.fromFunction(onDataChanged).release();
    pictureContext.onLoadingStatus = Callback.fromFunction(onLoadingStatus).release();
    pictureContext.onError = Callback.fromFunction(onError).release();
    pictureContext.enterView();
    data = pictureContext.data.control();
    loadSavedData();
  }

  void untouch() {
    pictureContext.onDataChanged = null;
    pictureContext.onLoadingStatus = null;
    pictureContext.onError = null;
    pictureContext.exitView();
    data?.release();
    pictureContext.release();
    preloadQueue.stop();
    loading = false;
  }

  void onPage(index) {
    setState(() {
      this.index = index;
    });
    preloadQueue.offset = index;
    KeyValue.set(_pageKey, index.toString());
  }

  void updateOrientation() {
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  void loadSavedData() {
    String key = pictureContext.projectKey;
    _directionKey = "$direction_key:$key";
    _deviceKey = "$device_key:$key";
    _pageKey = "$page_key:$cacheKey";
    String direction = KeyValue.get(_directionKey);
    switch (direction) {
      case 'vertical': {
        flipType = FlipType.Vertical;
        break;
      }
      case 'horizontal': {
        flipType = FlipType.Horizontal;
        break;
      }
      case 'horizontal_reverse': {
        flipType = FlipType.HorizontalReverse;
        break;
      }
      case 'right_to_left': {
        flipType = FlipType.RightToLeft;
        break;
      }
      case 'webtoon': {
        flipType = FlipType.Webtoon;
        break;
      }
      default: {
        flipType = FlipType.Horizontal;
      }
    }
    String device = KeyValue.get(_deviceKey);
    isLandscape = device == "landscape";
    String pageStr = KeyValue.get(_pageKey);
    if (pageStr != null) {
      try {
        index = int.parse(pageStr);
      } catch (e) {
      }
    }
  }

  bool _toastCoolDown = true;

  void onOverBound(BoundType type) {
    if (type == BoundType.Start) {
      Context context;
      if (widget.onChapterChanged != null && (context = widget.onChapterChanged(PictureFlipType.Prev)) != null) {
        untouch();
        pictureContext = context;
        touch();
        setState(() {
          index = - 1;
          pagerController?.dispose();
          pagerController  = PagerController(
              onPage: onPage,
              index: index,
              onOverBound: onOverBound,
          );
          // photoController.pageController.jumpToPage(index);
          if (!appBarDisplay) {
            appBarDisplay = true;
            // SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
            exitFullscreen();
            willDismissAppBar();
          }
        });
      } else if (_toastCoolDown) {
        _toastCoolDown = false;
        Fluttertoast.showToast(msg: kt("no_prev_chapter"), toastLength: Toast.LENGTH_SHORT);
        Future.delayed(Duration(seconds: 3)).then((value) => _toastCoolDown = true);
      }
    } else if (!loading) {
      Context context;
      if (widget.onChapterChanged != null && (context = widget.onChapterChanged(PictureFlipType.Next)) != null) {
        untouch();
        pictureContext = context;
        touch();
        setState(() {
          index = 0;
          pagerController?.dispose();
          pagerController = PagerController(
            onPage: onPage,
            index: index,
            onOverBound: onOverBound,
          );
          if (!appBarDisplay) {
            appBarDisplay = true;
            // SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
            exitFullscreen();
            willDismissAppBar();
          }
        });
      } else if (_toastCoolDown) {
        _toastCoolDown = false;
        Fluttertoast.showToast(msg: kt("no_next_chapter"), toastLength: Toast.LENGTH_SHORT);
        Future.delayed(Duration(seconds: 3)).then((value) => _toastCoolDown = true);
      }
    }
  }

  willDismissAppBar() {
    _timer = Timer(Duration(seconds: 4), () {
      setAppBarDisplay(false);
    });
  }

  @override
  initState() {
    pictureContext = widget.context;
    touch();
    willDismissAppBar();
    pagerController = PagerController(
      onPage: onPage,
      index: index,
      onOverBound: onOverBound
    );
    updateOrientation();
    channel = MethodChannel("com.ero.kinoko/volume_button");
    channel.invokeMethod("start");
    channel.setMethodCallHandler(onVolumeButtonClicked);
    super.initState();

    if (KeyValue.get("$viewed_key:picture") != "true") {
      Future.delayed(Duration(milliseconds: 300)).then((value) async {
        await showInstructionsDialog(context, 'assets/picture',
          entry: kt('lang'),
          iconColor: Theme.of(context).primaryColor,
          onPop: null,
          //     () async {
          //   // menuKey.currentState.showButtonMenu();
          //   await Future.delayed(Duration(milliseconds: 300));
          //   final renderObject = iconKey.currentContext.findRenderObject();
          //   Rect rect = renderObject?.paintBounds;
          //   var translation = renderObject?.getTransformTo(null)?.getTranslation();
          //   if (rect != null && translation != null) {
          //     return rect.shift(Offset(translation.x, translation.y));
          //   }
          //   return null;
          // }
        );
        KeyValue.set("$viewed_key:picture", "true");
        // if (menuKey.currentState.mounted)
        //   Navigator.of(menuKey.currentContext).pop();
      });
    }
  }

  @override
  dispose() {
    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
    pagerController.dispose();
    untouch();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    channel?.invokeMethod("stop");
    super.dispose();
  }

  void addToPreload(Array arr) {
    for (int i = 0 ,t = arr.length; i < t; ++i) {
      DataItem item = arr[i];
      preloadQueue.set(i, DownloadPictureItem(item.picture, cacheManager, headers: item.headers));
    }
  }

  Timer _hintTimer;
  void displayHint() {
    _hintTimer?.cancel();
    setState(() {
      _hintDisplay = true;
    });
    _hintTimer = Timer(Duration(seconds: 4), () {
      setState(() {
        _hintDisplay = false;
      });
    });
  }

  void tapAt(Offset position) {
    var rect = _canvasKey.currentContext?.findRenderObject()?.semanticBounds;
    if (rect == null) {
      onTapScreen();
    } else {
      var matrix = _hintMatrix(flipType);
      int ret = matrix.findValue(rect.size, position);
      if (ret > 0) {
        pagerController.next();
      } else if (ret < 0) {
        pagerController.prev();
      } else {
        onTapScreen();
      }
    }
  }
}