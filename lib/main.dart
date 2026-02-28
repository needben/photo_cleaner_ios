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

  Future<void> _initPlayer() async {
    if (_controller != null) return;
    final file = await widget.asset.file;
    if (file != null && mounted) {
      final controller = VideoPlayerController.file(file);
      _controller = controller;

      await controller.initialize();
      if (mounted) {
        await controller.setLooping(true);
        await controller.setVolume(0);
        setState(() => _isInitialized = true);
        // 延遲一點點播放，讓滑動動畫跑完
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) controller.play();
        });
      }
    }
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✨ 只有在「從不是 Current 變成 Current」時才初始化
    // 當滑掉卡片時，isCurrent 可能會變 false，但我們「不要」在那時做任何事
    // 讓 dispose 自己去處理清理就好
    if (widget.isCurrent && !oldWidget.isCurrent && !_isInitialized) {
      _initPlayer();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
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
  List<String> _pendingDeleteIds = []; // 存放準備刪除的 ID
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

  // 執行批次刪除
  Future<void> _handleBulkDelete() async {
    if (_pendingDeleteIds.isEmpty) return;

    try {
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(
        _pendingDeleteIds,
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
          SnackBar(content: Text("成功清理 ${deletedIds.length} 個檔案！")),
        );
      }
    } catch (e) {
      debugPrint("刪除出錯: $e");
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
    final DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("相簿大掃除"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
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
                          onSwipe: (previousIndex, currentIndex, direction) {
                            // 1. 處理資料邏輯 (不影響 UI)
                            if (direction == CardSwiperDirection.left) {
                              _pendingDeleteIds.add(_photos[previousIndex].id);
                            }

                            // 2. 只重置提示文字 (讓動畫流暢)
                            setState(() {
                              _keepOpacity = 0.0;
                              _deleteOpacity = 0.0;
                            });

                            // 3. ✨ 關鍵延遲：等大卡片飛出一段距離後，再更新索引
                            // 這樣下方滾輪就不會在大卡片還沒消失前就突然跳動
                            Future.delayed(
                              const Duration(milliseconds: 200),
                              () {
                                if (mounted) {
                                  setState(() {
                                    _currentIndex = currentIndex ?? 0;
                                  });
                                  // 滾動下方清單也放在這裡，視覺上會更同步
                                  _scrollToThumbnail(_currentIndex);
                                }
                              },
                            );

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

                            return Container(
                              // ✨ 回歸穩定 ID，不要加 $index
                              key: ValueKey(asset.id),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Stack(
                                  children: [
                                    // 底圖 (縮圖)
                                    Positioned.fill(
                                      child: AssetEntityImage(
                                        asset,
                                        isOriginal: false,
                                        thumbnailSize: const ThumbnailSize(
                                          800,
                                          800,
                                        ),
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      ),
                                    ),

                                    if (asset.type == AssetType.video)
                                      Positioned.fill(
                                        child: VideoCard(
                                          key: ValueKey('video_${asset.id}'),
                                          asset: asset,
                                          // 這裡傳入 index == _currentIndex 是對的
                                          isCurrent: index == _currentIndex,
                                        ),
                                      ),

                                    // 照片日期顯示
                                    Positioned(
                                      top: 15,
                                      left: 15,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          formatter.format(
                                            asset.createDateTime,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
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
                      Positioned(
                        right: 30,
                        top: MediaQuery.of(context).size.height * 0.4,
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
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
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
      floatingActionButton: _pendingDeleteIds.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 80), // 調整這個數值，數字越大越高
              child: FloatingActionButton.extended(
                onPressed: _handleBulkDelete,
                label: Text("確認刪除 (${_pendingDeleteIds.length})"),
                icon: const Icon(Icons.delete_forever),
                backgroundColor: Colors.redAccent,
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
