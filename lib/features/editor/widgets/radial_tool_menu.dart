import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/colors.dart';

class RadialMenuItem {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;
  final bool isAi;

  const RadialMenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    this.onTap,
    this.isAi = false,
  });
}

class RadialToolMenu extends StatefulWidget {
  final List<RadialMenuItem> items;
  final double radius;

  const RadialToolMenu({super.key, required this.items, this.radius = 100.0});

  @override
  State<RadialToolMenu> createState() => _RadialToolMenuState();
}

class _RadialToolMenuState extends State<RadialToolMenu> with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  int? _selectedIndex;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 350), vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
        _selectedIndex = null;
      }
    });
  }

  void _selectItem(int index) {
    if (_selectedIndex == index) {
      widget.items[index].onTap?.call();
      _toggle();
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    const menuSize = 300.0;

    return SizedBox(
      width: menuSize,
      height: menuSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Glassmorphism круг-фон (только когда открыто)
          if (_isOpen)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _controller.value,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.3),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // 2. 9 кнопок по полному кругу
          ...List.generate(items.length, (index) {
            final item = items[index];
            final angle = -math.pi / 2 + (index * (2 * math.pi / items.length));
            final dx = widget.radius * math.cos(angle);
            final dy = widget.radius * math.sin(angle);

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final progress = _controller.value;
                return Positioned(
                  left: menuSize / 2 + dx * progress - 27, // -27 потому что ширина кнопки теперь 54 (54/2)
                  top: menuSize / 2 + dy * progress - 27,
                  child: IgnorePointer(
                    ignoring: !_isOpen,
                    child: Opacity(
                      opacity: progress,
                      child: Transform.scale(
                        scale: 0.3 + (0.7 * progress),
                        child: _RadialButton(
                          item: item,
                          isSelected: _selectedIndex == index,
                          onTap: () => _selectItem(index),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          // 3. Центральная кнопка: видна ВСЕГДА, в центре круга
          GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isOpen ? 76 : 64,
              height: _isOpen ? 76 : 64,
              padding: EdgeInsets.all(_isOpen ? 6 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOpen ? Colors.transparent : AppColors.primary,
                border: Border.all(
                  color: _isOpen ? AppColors.border : AppColors.primaryLight,
                  width: 2,
                ),
                boxShadow: _isOpen
                    ? []
                    : [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isOpen ? AppColors.surfaceLight : AppColors.primary,
                ),
                child: Icon(
                  _isOpen ? Icons.close : Icons.tune,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),

          // 4. ✅ Tooltip (ВСПЛЫВАЮЩАЯ ПОДСКАЗКА) - В САМОМ КОНЦЕ STACK, чтобы быть поверх всего
          if (_isOpen && _selectedIndex != null)
            Positioned(
              top: 70, // 👈 Подняли выше (между центральной кнопкой и верхним рядом)
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // 👈 Чуть крупнее отступы
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    items[_selectedIndex!].label,
                    style: GoogleFonts.manrope(
                      fontSize: 14,          // 👈 Увеличили шрифт
                      fontWeight: FontWeight.w700, // 👈 Сделали жирнее
                      color: Colors.white,
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

class _RadialButton extends StatelessWidget {
  final RadialMenuItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _RadialButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,   // 👈 Увеличенный размер
        height: 54,  
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected 
              ? AppColors.primary 
              : Colors.white.withValues(alpha: 0.15), // 👈 Стеклянный фон
          border: Border.all(
            color: isSelected 
                ? AppColors.primaryLight 
                : Colors.white.withValues(alpha: 0.3),  // 👈 Светлая обводка
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]
              : (item.isAi 
                  ? [BoxShadow(color: AppColors.aiAccent.withValues(alpha: 0.4), blurRadius: 8)]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)]),
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppColors.primary : Colors.transparent,
          ),
          child: Icon(
            item.icon,
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9), // 👈 Белые иконки
            size: 24,  // 👈 Увеличенная иконка
          ),
        ),
      ),
    );
  }
}