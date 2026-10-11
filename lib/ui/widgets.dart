import 'package:flutter/material.dart';

const bg = Color(0xFFFFF3E0);
const inkColor = Color(0xFF5D4037);

/// 화면 위 카드·알림에 다는 부드러운 그림자.
const softShadow = [BoxShadow(color: Color(0x30000000), blurRadius: 10, offset: Offset(0, 4))];

class Coins extends StatelessWidget {
  final int amount;
  final double size;
  const Coins(this.amount, {super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.monetization_on, color: const Color(0xFFFFB300), size: size + 2),
        const SizedBox(width: 4),
        Text('$amount',
            style: TextStyle(fontSize: size, color: amount < 0 ? Colors.red : inkColor)),
      ]);
}

/// 둥글고 통통한 버튼. 누르면 살짝 눌린다.
class BubbleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Widget? trailing;
  const BubbleButton(this.label, {super.key, this.onTap, this.color = const Color(0xFFFFB74D), this.trailing});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Material(
      color: on ? color : const Color(0xFFE0E0E0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: inkColor, width: 2.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          // 넓은 자리에서는 가운데, 좁은 자리에서는 글자 크기만큼
          child: Center(
            widthFactor: 1,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(label,
                  style: TextStyle(fontSize: 18, color: on ? inkColor : Colors.black38)),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ]),
          ),
        ),
      ),
    );
  }
}
