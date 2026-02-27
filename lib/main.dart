import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:intl/intl.dart';

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
      double targetOffset = index * 78.0;
      double screenWidth = MediaQuery.of(context).size.width;
      double centerOffset = targetOffset - (screenWidth / 2) + 39.0;

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
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: AssetEntityImage(
                                    asset,
                                    isOriginal: false,
                                    thumbnailSize: const ThumbnailSize(
                                      1000,
                                      1000,
                                    ),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                ),

                                // 影片標籤：如果是影片，在中間顯示播放圖示
                                if (asset.type == AssetType.video)
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white70,
                                      size: 80,
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
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                        return GestureDetector(
                          onTap: () => _onThumbTap(index),
                          child: Container(
                            decoration: BoxDecoration(
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 3)
                                  : Border.all(
                                      color: Colors.transparent,
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
                                      200,
                                    ),
                                    fit: BoxFit.cover,
                                    width: 70,
                                    height: 70,
                                  ),
                                  // 縮圖上的影片標示
                                  if (_photos[index].type == AssetType.video)
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
                        );
                      },
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
