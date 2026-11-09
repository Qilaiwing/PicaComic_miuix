import 'package:flutter/material.dart';

typedef ActionFunc = void Function();

enum ComicType {
  picacg,
  ehentai,
  jm,
  hitomi,
  htManga,
  htFavorite,
  nhentai,
  other;

  @override
  toString() => name;
}

const String webUA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36";

//App版本
const appVersion = "4.3.1-miuix";

//定义宽屏设备的临界值
const changePoint = 600;
const changePoint2 = 1300;

/// 主题色板 —— HyperOS 风格种子色
///
/// 这里用的是柔化过的参考色，而不是 Material 的 Accent 系列。
/// `Colors.redAccent` / `blueAccent` 这类色饱和度太高，直接当种子去生成
/// 配色会偏「电子味」，和 HyperOS 那种灰中带彩的质感差很远。
///
/// 每一项都是一个 HCT 种子色，会经 `miuixColorsFromSeed` 展开成整套语义色。
List<Color> get themePalette => const [
  Color(0xFF3482FF), // 小米蓝
  Color(0xFFE86A8A), // 玫瑰粉
  Color(0xFF9B7EDE), // 薰衣草紫
  Color(0xFF6B7FD7), // 蓝紫 / 靛青
  Color(0xFF2E9BD6), // 天蓝
  Color(0xFF2FB8C6), // 青 / 湖蓝
  Color(0xFF2AA9A0), // 蓝绿
  Color(0xFF5BB98C), // 抹茶绿
  Color(0xFF8FBF4D), // 青柠
  Color(0xFFD9A62E), // 金黄
  Color(0xFFE39A3C), // 琥珀
  Color(0xFFF2764B), // 珊瑚橙
];

/// 是否使用系统动态取色（Monet）
///
/// [setting] 是 `appdata.settings[27]`，索引 0 表示跟随系统壁纸。
bool useDynamicColor(int setting) => setting == 0;

/// 根据设置索引取得当前选中的主题种子色
///
/// [setting] 是 `appdata.settings[27]`；为 0（动态取色）或越界时兜底小米蓝。
Color themeSeedColor(int setting) {
  if (setting <= 0 || setting > themePalette.length) {
    return themePalette.first;
  }
  return themePalette[setting - 1];
}

const builtInSources = [
  "picacg",
  "ehentai",
  "jm",
  "hitomi",
  "htmanga",
  "nhentai"
];