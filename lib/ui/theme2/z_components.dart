import 'package:flutter/material.dart';

import 'tokens.dart';

/// 圆角卡片：浅色用纯白表面，深色用深色表面一级。
class ZCard extends StatelessWidget {
  const ZCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = Zr.card,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isLight ? Zc.surface : Zc.darkSurface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// 胶囊主按钮：启用时用品牌渐变，禁用时降级为纯色且不可点。
class ZPrimaryButton extends StatelessWidget {
  const ZPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final disabledColor = isLight ? Zc.subtle : Zc.darkSurface2;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: enabled ? Zbrand.gradient : null,
            color: enabled ? null : disabledColor,
            borderRadius: BorderRadius.circular(Zr.button),
          ),
          child: Text(
            label,
            style: Zt.headline.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// 圆角胶囊小标签（micro 字阶），默认用品牌色，可用 color 覆盖。
class ZBadge extends StatelessWidget {  const ZBadge({
    super.key,
    required this.text,
    this.color,
  });

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final background = color ?? (isLight ? Zc.brandFresh : Zc.darkBrand);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Zr.button),
      ),
      child: Text(
        text,
        style: Zt.micro.copyWith(color: Colors.white),
      ),
    );
  }
}

/// 次级胶囊按钮：描边 + 文本色，用于"详情""更多"这类非主行动。
class ZGhostButton extends StatelessWidget {
  const ZGhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tint,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final color = tint ?? (isLight ? Zc.textPrimary : Zc.darkTextPrimary);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Zr.button),
            border: Border.all(color: isLight ? Zc.separator : const Color(0x33FFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
              ],
              Text(label, style: Zt.headline.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
