import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';

//////
//git add .
//git commit -m "fix: corrected filmstrip center offset calculation for real-time sync"
//git push
//////
void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PhotoCleanerApp(),
    ),
  );
}

class PhotoCleanerApp extends StatefulWidget {
  const PhotoCleanerApp({super.key});

  @override
  State<PhotoCleanerApp> createState() => _PhotoCleanerAppState();
}

class VideoCard extends StatefulWidget {
  final AssetEntity asset;
  final bool isCurrent;

  const VideoCard({required this.asset, required this.isCurrent, super.key});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.isCurrent) _initPlayer();
  }

  // 🌟 關鍵修正：處理 Widget 複用時的資料更新
  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 情況 A：照片 ID 換了（滑到了下一個影片）
    if (widget.asset.id != oldWidget.asset.id) {
      _disposeController(); // 先清理舊的
      if (widget.isCurrent) _initPlayer(); // 如果是當前張就初始化新的
    }
    // 情況 B：ID 沒換，但從「非當前」變成「當前」（例如滑回來）
    else if (widget.isCurrent && !oldWidget.isCurrent && !_isInitialized) {
      _initPlayer();
    }
    // 情況 C：滑開了，停止播放以省電/省資源 (選配)
    else if (!widget.isCurrent && oldWidget.isCurrent) {
      _controller?.pause();
    }
  }

  Future<void> _initPlayer() async {
    if (_controller != null) return;

    final file = await widget.asset.file;
    if (file != null && mounted) {
      final controller = VideoPlayerController.file(file);
      _controller = controller;

      try {
        await controller.initialize();
        if (mounted) {
          await controller.setLooping(true);
          await controller.setVolume(0);
          setState(() => _isInitialized = true);

          // 確保只有在還是 Current 的情況下才播放
          if (widget.isCurrent) {
            controller.play();
          }
        }
      } catch (e) {
        debugPrint("影片初始化失敗: $e");
      }
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // ✨ 永遠顯示一張縮圖作為底圖，防止影片載入前的黑屏閃動
          Positioned.fill(
            child: AssetEntityImage(
              widget.asset,
              isOriginal: false,
              fit: BoxFit.contain,
              gaplessPlayback: true, // 關鍵：無縫播放縮圖
            ),
          ),
          if (_isInitialized && _controller != null)
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoCleanerAppState extends State<PhotoCleanerApp> {
  List<AssetEntity> _photos = [];
  Set<String> _pendingDeleteIds = {}; // 存放準備刪除的 ID ㄝ, Set 自動保證元素唯一性
  bool _isLoading = true;
  int _currentIndex = 0; // 追蹤目前卡片的索引
  final CardSwiperController _swiperController = CardSwiperController();
  final ScrollController _thumbScrollController =
      ScrollController(); // 底部縮圖滑動控制器

  // 控制滑動時的提示字體不透明度 (0.0 ~ 1.0)
  double _keepOpacity = 0.0;
  double _deleteOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
  }

  @override
  void dispose() {
    _swiperController.dispose();
    _thumbScrollController.dispose();
    super.dispose();
  }

  // 讀取相片與影片邏輯
  Future<void> _fetchPhotos() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      // 改為 RequestType.common 同時獲取圖片與影片
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
      );

      List<AssetEntity> tempPhotos = [];
      Set<String> seenIds = {};

      for (var album in albums) {
        final assets = await album.getAssetListPaged(page: 0, size: 80);
        for (var asset in assets) {
          if (!seenIds.contains(asset.id)) {
            tempPhotos.add(asset);
            seenIds.add(asset.id);
          }
        }
      }

      tempPhotos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      setState(() {
        _photos = tempPhotos;
        _isLoading = false;
        _currentIndex = 0;
      });
    } else {
      PhotoManager.openSetting();
      setState(() => _isLoading = false);
    }
  }

  void _restorePhoto(String id) {
    setState(() {
      _pendingDeleteIds.remove(id);
    });
    // 如果清單空了，自動關閉預覽視窗
    if (_pendingDeleteIds.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  void _showPendingDeleteList() {
    // 過濾出所有在待刪除清單中的 AssetEntity
    final List<AssetEntity> pendingAssets = _photos
        .where((p) => _pendingDeleteIds.contains(p.id))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          // 使用 StatefulBuilder 讓視窗內可以即時操作還原
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 在 _showPendingDeleteList 方法內的 Row 中修改：
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "待刪除清單 (${pendingAssets.length})",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // --- 新增：全部還原按鈕 ---
                      if (pendingAssets.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(
                            Icons.settings_backup_restore,
                            size: 18,
                          ),
                          label: const Text("全部還原"),
                          onPressed: () {
                            setState(() {
                              _pendingDeleteIds.clear(); // 清空待刪除清單
                            });
                            Navigator.pop(context); // 關閉 BottomSheet
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("已還原所有照片")),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.greenAccent,
                          ),
                        ),
                      // ----------------------
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "關閉",
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                      itemCount: pendingAssets.length,
                      itemBuilder: (context, index) {
                        final asset = pendingAssets[index];
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AssetEntityImage(
                                  asset,
                                  isOriginal: false,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            // 右上角的「還原」按鈕
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () {
                                  // 1. 更新外部 State
                                  _restorePhoto(asset.id);
                                  // 2. 更新 Modal 內部的資料並刷新
                                  setModalState(() {
                                    pendingAssets.removeAt(index);
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.undo,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                      ),
                      onPressed: () {
                        Navigator.pop(context); // 先關視窗
                        _executeFinalDelete(); // 執行真正的刪除
                      },
                      child: const Text(
                        "確認永久刪除",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeFinalDelete() async {
    try {
      // 這裡才真正動用到 PhotoManager 的硬體刪除權限
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(
        _pendingDeleteIds.toList(),
      );

      if (deletedIds.isNotEmpty) {
        setState(() {
          _photos.removeWhere((photo) => deletedIds.contains(photo.id));
          _pendingDeleteIds.clear();
          if (_photos.isNotEmpty) {
            _currentIndex = _currentIndex.clamp(0, _photos.length - 1);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("已從裝置中刪除 ${deletedIds.length} 個檔案")),
        );
      }
    } catch (e) {
      debugPrint("刪除失敗: $e");
    }
  }

  // 當使用者在底部縮圖清單點擊時，跳轉卡片
  void _onThumbTap(int index) {
    setState(() {
      _currentIndex = index;
    });
    _swiperController.moveTo(index);
  }

  void _scrollToThumbnail(int index) {
    if (_thumbScrollController.hasClients) {
      double itemWidthWithSpacing = 28.0;
      // 因為 Padding 已經處理了置中，所以 offset 只要算 index * 寬度即可
      double targetOffset = index * itemWidthWithSpacing;

      _thumbScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat formatter = DateFormat('MMM dd, yyyy HH:mm:ss');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("相簿大掃除"),
        centerTitle: true, // ✨ 讓標題置中，左右按鈕對稱
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _pendingDeleteIds.isEmpty
            ? null
            : Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.delete_sweep,
                      color: Colors.redAccent,
                    ),
                    onPressed: _showPendingDeleteList, // 呼叫剛才寫好的預覽視窗
                  ),
                  // 🔴 顯示待刪除數量的紅點小標籤
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${_pendingDeleteIds.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
        // 👉 右側按鈕：重新整理
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchPhotos();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
          ? const Center(
              child: Text("相簿空空如也", style: TextStyle(color: Colors.white)),
            )
          : Column(
              children: [
                Expanded(
                  flex: 8,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 20,
                        ),
                        child: CardSwiper(
                          controller: _swiperController,
                          cardsCount: _photos.length,
                          numberOfCardsDisplayed: 2,
                          maxAngle: 30, // 旋轉角度，讓滑出去的動作更自然
                          threshold: 40, // 觸發滑掉的門檻像素，越小越靈敏
                          backCardOffset: const Offset(
                            0,
                            0,
                          ), // 讓背景卡片不要露出來，視覺更乾淨
                          onSwipe: (previousIndex, currentIndex, direction) {
                            // 1. 立即更新索引，讓 UI 同步 (文字變亮、底圖切換)
                            setState(() {
                              // 處理資料邏輯：如果向左滑，加入待刪除清單
                              if (direction == CardSwiperDirection.left) {
                                final String assetId =
                                    _photos[previousIndex].id;
                                if (!_pendingDeleteIds.contains(assetId)) {
                                  _pendingDeleteIds.add(assetId);
                                }
                              }

                              // 關鍵：立刻更新 currentIndex，不要 delay
                              _currentIndex = currentIndex ?? 0;

                              // 重置提示文字透明度
                              _keepOpacity = 0.0;
                              _deleteOpacity = 0.0;
                            });

                            // 2. 底部滾輪滑動可以稍微延遲一點點，或者保持同步
                            // 如果覺得滾輪跳太快，這裡可以用較短的延遲，但 currentIndex 必須先改
                            _scrollToThumbnail(_currentIndex);

                            return true;
                          },
                          onSwipeDirectionChange:
                              (horizontalDirection, verticalDirection) {
                                setState(() {
                                  if (horizontalDirection ==
                                      CardSwiperDirection.right) {
                                    _keepOpacity = 1.0;
                                    _deleteOpacity = 0.0;
                                  } else if (horizontalDirection ==
                                      CardSwiperDirection.left) {
                                    _keepOpacity = 0.0;
                                    _deleteOpacity = 1.0;
                                  } else {
                                    _keepOpacity = 0.0;
                                    _deleteOpacity = 0.0;
                                  }
                                });
                              },
                          cardBuilder: (context, index, horizontal, vertical) {
                            final asset = _photos[index];
                            double aspectRatio = asset.width > 0
                                ? asset.width / asset.height
                                : 1.0;

                            // 🌟 使用同一個判斷標準
                            bool isCurrent = index == _currentIndex;

                            return Container(
                              width: double.infinity,
                              height: double.infinity,
                              color: Colors.transparent,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 📅 1. 日期：使用 200ms 動畫
                                    AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 50,
                                      ),
                                      opacity: isCurrent ? 1.0 : 0.3,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          formatter.format(
                                            asset.createDateTime,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 🖼️ 2. 照片卡片
                                    Flexible(
                                      child: AspectRatio(
                                        aspectRatio: aspectRatio,
                                        child: Container(
                                          key: ValueKey(asset.id),
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            boxShadow: [
                                              // 只有當前照片有陰影
                                              if (isCurrent)
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.5),
                                                  blurRadius: 25,
                                                  spreadRadius: 5,
                                                ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: Stack(
                                              children: [
                                                // 照片底圖
                                                Positioned.fill(
                                                  child: AssetEntityImage(
                                                    asset,
                                                    isOriginal: false,
                                                    thumbnailSize:
                                                        const ThumbnailSize(
                                                          1200,
                                                          1200,
                                                        ),
                                                    fit: BoxFit.cover,
                                                    gaplessPlayback: true,
                                                  ),
                                                ),

                                                // 影片層
                                                if (asset.type ==
                                                    AssetType.video)
                                                  Positioned.fill(
                                                    child: VideoCard(
                                                      key: ValueKey(
                                                        'video_${asset.id}',
                                                      ),
                                                      asset: asset,
                                                      isCurrent: isCurrent,
                                                    ),
                                                  ),

                                                // 🌟 關鍵修正：照片遮罩也改用 AnimatedOpacity
                                                // 移除 if (isNotCurrent)，讓 Widget 永遠存在，只改透明度
                                                Positioned.fill(
                                                  child: AnimatedOpacity(
                                                    duration: const Duration(
                                                      milliseconds: 200,
                                                    ),
                                                    // 當是 current 時，遮罩透明度為 0 (全亮)
                                                    // 當不是 current 時，遮罩透明度為 0.6 (變暗)
                                                    opacity: isCurrent
                                                        ? 0.0
                                                        : 0.6,
                                                    child: Container(
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // 滑動提示文字
                      Positioned(
                        left: 30,
                        top: MediaQuery.of(context).size.height * 0.4,
                        child: IgnorePointer(
                          // 🌟 加上這一層，手勢會直接穿透
                          child: Opacity(
                            opacity: _keepOpacity,
                            child: const Text(
                              "Keep",
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 60,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 10),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 30,
                        top: MediaQuery.of(context).size.height * 0.4,
                        child: IgnorePointer(
                          // 🌟 加上這一層，手勢會直接穿透
                          child: Opacity(
                            opacity: _deleteOpacity,
                            child: const Text(
                              "Delete",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 60,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 10),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 底部縮圖清單
                Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: SizedBox(
                    height: 65,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        // ✨ 改為監聽 ScrollUpdateNotification，實現「按住滑動時」即時切換
                        if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) {
                          final double itemWidth = 28.0; // 26寬 + 2間距

                          double currentOffset = _thumbScrollController.offset;
                          int index = (currentOffset / itemWidth)
                              .round(); // 使用 round() 會比 floor() 在對齊時更精準

                          index = index.clamp(0, _photos.length - 1);
                          // ✨ 只有當 index 真的改變時才觸發 setState，這對效能至關重要
                          if (index != _currentIndex) {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _currentIndex = index;
                            });
                            // 即時同步上方大卡片
                            _swiperController.moveTo(index);
                          }
                        }
                        return true;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        color: Colors.black,
                        child: ListView.separated(
                          controller: _thumbScrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          // 確保左右兩端都能滑到中間
                          padding: EdgeInsets.symmetric(
                            horizontal:
                                MediaQuery.of(context).size.width / 2 - 13,
                          ),
                          itemCount: _photos.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 2),
                          itemBuilder: (context, index) {
                            bool isSelected = (index == _currentIndex);
                            return Center(
                              child: GestureDetector(
                                onTap: () => _onThumbTap(index), // 點擊依然有效
                                child: Container(
                                  width: 26,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: AssetEntityImage(
                                      _photos[index],
                                      isOriginal: false,
                                      thumbnailSize: const ThumbnailSize(
                                        100,
                                        200,
                                      ),
                                      fit: BoxFit.cover,
                                      width: 20,
                                      height: 40,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
