import 'package:flutter/material.dart';
import 'image_browser.dart'; // 我们稍后会创建这个组件

class EditorView extends StatelessWidget {
  const EditorView({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧：图片浏览器，占据 6 份空间
        const Expanded(
          flex: 6,
          child: ImageBrowser(),
        ),
        // 分隔线
        const VerticalDivider(width: 1, thickness: 1),
        // 右侧：其他功能区，占据 4 份空间
        Expanded(
          flex: 4,
          child: Container(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
            child: const Center(
              child: Text('Right Panel (4/10)'),
            ),
          ),
        ),
      ],
    );
  }
}
