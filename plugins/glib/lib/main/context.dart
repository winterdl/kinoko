
import '../core/core.dart';
import '../core/callback.dart';
import '../core/array.dart';

class Context extends Base {
  static reg() {
    Base.reg(Context, "gs::Context", Base)
    ..constructor = ((id)=>Context().setID(id));
  }
  
  bool isReady() => call("isReady");
  void reload([Map data]) => call("reload", argv: [data]);
  void loadMore() => call("loadMore");
  void enterView() => call("enterView");
  void exitView() => call("exitView");

  void clearData() => call("clearData");

  void saveData() => call("saveData");

  static const int DataReload = 1;
  static const int DataAppend = 2;

  Callback _onDataChanged;
  set onDataChanged(Callback cb) {
    _onDataChanged?.release();
    _onDataChanged = cb == null ? null : cb.control();
    call("setOnDataChanged", argv: [cb]);
  }

  Callback _onLoadingStatus;
  set onLoadingStatus(Callback cb) {
    _onLoadingStatus?.release();
    _onLoadingStatus = cb == null ? null : cb.control();
    call("setOnLoadingStatus", argv: [cb]);
  }

  Callback _onError;
  set onError(Callback cb) {
    _onError?.release();
    _onError = cb == null ? null : cb.control();
    call("setOnError", argv: [cb]);
  }

  Callback _onReloadComplete;
  set onReloadComplete(Callback cb) {
    _onReloadComplete?.release();
    _onReloadComplete = cb == null ? null : cb.control();
    call("setOnReloadComplete", argv: [cb]);
  }

  bool get autoReload => call("isAutoReload");
  set autoReload(bool v) => call("setAutoReload", argv: [v]);

  int get expireTime => call("getExpireTime");
  set expireTime(int v) => call("setExpireTime", argv: [v]);

  Array get data => call("getData");
  dynamic get infoData => call("getInfoData");
  set infoData(dynamic data) => call("setInfoData", argv: [data]);

  String get projectKey => call("getProjectKey");

  static Array searchKeys(String key, int limit) => Base.s_call(Context, "searchKeys", argv: [key, limit]);
  static void removeSearchKey(String key) => Base.s_call(Context, "removeSearchKey", argv: [key]);

  @override
  void destroy() {
    _onDataChanged?.release();
    _onLoadingStatus?.release();
    _onError?.release();
    _onReloadComplete?.release();
    super.destroy();
  }

  dynamic getSetting(String key) => call("getSetting", argv: [key]);
  void setSetting(String key, dynamic value) => call("setSetting", argv: [key, value]);

  String get temp => call("getTemp");
  // String get itemTemp => call("getItemTemp");

  dynamic applyFunction(String name, Array args) => call("applyFunction", argv: [name, args]);

  Callback get onCall => call("getOnCall");
  set onCall(Callback v) => call("setOnCall", argv: [v]);
}

class LibraryContext extends Base {
  static void reg() {
    Base.reg(LibraryContext, "gs::LibraryContext", Base);
  }

  LibraryContext.allocate() {
    super.allocate([]);
  }

  Array get data => call("getData");

  bool parseLibrary(String str) => call("parseLibrary", argv: [str]);
  bool insertLibrary(String url, String branch) => call("insertLibrary", argv: [url, branch]);
  bool removeLibrary(String url) => call("removeLibrary", argv: [url]);
}