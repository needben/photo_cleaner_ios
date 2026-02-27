import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

void main() {
  runApp(const PhotoCleanerApp());
}

class PhotoCleanerApp extends StatelessWidget {
  const PhotoCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '相簿大掃除',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SwipeDeleterScreen(),
    );
  }
}

class SwipeDeleterScreen extends StatefulWidget {
  const SwipeDeleterScreen({super.key});

  @override
  State<SwipeDeleterScreen> createState() => _SwipeDeleterScreenState();
}

class _SwipeDeleterScreenState extends State<SwipeDeleterScreen> {
  List<AssetEntity> _photos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPhotos(); // App 啟動時讀取照片
  }

  // 核心功能：抓取手機相簿照片
  Future<void> _fetchPhotos() async {
    // 確保請求的是最新版權限
    final PermissionState ps = await PhotoManager.requestPermissionExtend();

    if (ps.isAuth || ps.hasAccess) {
      // 取得「所有」相簿，不限於「OnlyAll」
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );

      List<AssetEntity> tempPhotos = [];

      // 遍歷所有相簿（例如：Camera, WhatsApp, Download 等）
      for (var album in albums) {
        // 每個相簿抓前 50 張
        final assets = await album.getAssetListPaged(page: 0, size: 50);
        tempPhotos.addAll(assets);
      }

      // 根據日期排序，最新在前面
      tempPhotos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      setState(() {
        _photos = tempPhotos;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      // 如果權限還是沒過，這行會幫你跳轉到設定頁面
      PhotoManager.openSetting();
    }
  }

  // 核心功能：刪除照片
  Future<void> _deletePhoto(AssetEntity entity) async {
    try {
      // 調用系統刪除視窗 (iOS 會彈出系統確認框)
      final List<String> result = await PhotoManager.editor.deleteWithIds([
        entity.id,
      ]);
      print("刪除結果: $result");
    } catch (e) {
      print("刪除失敗: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("相簿大掃除")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // 讀取中
          : _photos.isEmpty
          ? const Center(child: Text("相簿裡沒有照片或未獲得權限"))
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "⬅️ 左滑保留 | 右滑刪除 ➡️",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Expanded(
                  child: CardSwiper(
                    cardsCount: _photos.length,
                    onSwipe: (previousIndex, currentIndex, direction) {
                      if (direction == CardSwiperDirection.right) {
                        // 右滑：執行刪除
                        _deletePhoto(_photos[previousIndex]);
                      }
                      return true;
                    },
                    cardBuilder:
                        (
                          context,
                          index,
                          horizontalThreshold,
                          verticalThreshold,
                        ) {
                          final asset = _photos[index];
                          // 使用 AssetEntityImage 顯示手機本地照片
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: AssetEntityImage(
                              _photos[index],
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize(1000, 1000),
                              fit: BoxFit.cover,
                            ),
                          );
                        },
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}
