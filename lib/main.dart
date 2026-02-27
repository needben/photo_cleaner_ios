import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.isCurrent) _initPlayer();
  }

  Future<void> _initPlayer() async {
    final file = await widget.asset.file;
    if (file != null) {
      _controller = VideoPlayerController.file(file)
        ..setLooping(true)
        ..setVolume(0) // 預設靜音比較不吵
        ..initialize().then((_) => setState(() => _controller?.play()));
    }
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent && _controller == null) {
      _initPlayer();
    } else if (!widget.isCurrent && _controller != null) {
      _controller?.dispose();
      _controller = null;
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
      color: Colors.black, // 背景設為黑色，填充橫向影片留下的上下黑邊
      child: _controller != null && _controller!.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            )
          : AssetEntityImage(
              widget.asset,
              isOriginal: false,
              fit: BoxFit.contain, // 這裡也改成 contain
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
      // 66 (寬) + 8 (間距) = 74
      double targetOffset = index * 74.0;

      double screenWidth = MediaQuery.of(context).size.width;
      // 置中計算：目標位移 - (螢幕一半) + (一個縮圖的一半)
      double centerOffset = targetOffset - (screenWidth / 2) + 33;

      _thumbScrollController.animateTo(
        centerOffset.clamp(0, _thumbScrollController.position.maxScrollExtent),
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
                          onSwipe: (previousIndex, currentIndex, direction) {
                            setState(() {
                              _keepOpacity = 0.0;
                              _deleteOpacity = 0.0;
                              _currentIndex = currentIndex ?? 0;
                            });

                            _scrollToThumbnail(_currentIndex);

                            // 左滑刪除(Delete)
                            if (direction == CardSwiperDirection.left) {
                              setState(() {
                                _pendingDeleteIds.add(
                                  _photos[previousIndex].id,
                                );
                              });
                            }
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
                            // 判斷這張卡片是否為目前使用者正在看的那張
                            bool isCurrent = (index == _currentIndex);

                            return Stack(
                              children: [
                                // 背景主體：判斷是影片還是照片
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: asset.type == AssetType.video
                                      ? VideoCard(
                                          asset: asset,
                                          isCurrent: isCurrent, // 只有目前這張會自動播放
                                        )
                                      : AssetEntityImage(
                                          asset,
                                          isOriginal: false,
                                          thumbnailSize: const ThumbnailSize(
                                            1000,
                                            1000,
                                          ),
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                          height: double.infinity,
                                        ),
                                ),

                                // 影片標籤：如果是影片且「不是」正在播放的卡片，才顯示播放圖示
                                if (asset.type == AssetType.video && !isCurrent)
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white70,
                                      size: 80,
                                    ),
                                  ),

                                // 照片日期顯示 (維持原樣)
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
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      formatter.format(asset.createDateTime),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                  padding: const EdgeInsets.only(
                    bottom: 20,
                  ), // ✨ 1. 調整這裡，增加與底部的空間 (可根據按鈕位置調整)
                  child: SizedBox(
                    height: 70, // 稍微調高一點以容納 4:3 的比例
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      color: Colors.black,
                      child: ListView.separated(
                        controller: _thumbScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _photos.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          bool isSelected = (index == _currentIndex);
                          return Center(
                            child: GestureDetector(
                              onTap: () => _onThumbTap(index),
                              child: Container(
                                // ✨ 2. 調整寬高比為 4:3 (加上邊框寬度)
                                // 圖片高度設為 45 -> 寬度則為 45 * 1.33 = 60
                                width: 66, // 60 (圖片寬) + 3*2 (左右邊框)
                                height: 51, // 45 (圖片高) + 3*2 (上下邊框)
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Stack(
                                    children: [
                                      AssetEntityImage(
                                        _photos[index],
                                        isOriginal: false,
                                        thumbnailSize: const ThumbnailSize(
                                          200,
                                          150,
                                        ), // 解析度也配合 4:3
                                        fit: BoxFit.cover, // 填滿 4:3 的框
                                        width: 60,
                                        height: 45,
                                      ),
                                      if (_photos[index].type ==
                                          AssetType.video)
                                        const Positioned(
                                          right: 2,
                                          bottom: 2,
                                          child: Icon(
                                            Icons.videocam,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                    ],
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
              ],
            ),
      floatingActionButton: _pendingDeleteIds.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _handleBulkDelete,
              label: Text("確認刪除 (${_pendingDeleteIds.length})"),
              icon: const Icon(Icons.delete_forever),
              backgroundColor: Colors.redAccent,
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
