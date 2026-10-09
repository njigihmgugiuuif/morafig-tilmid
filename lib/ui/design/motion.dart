import 'dart:async';

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Page transition for every route of the app (installed once in the theme,
/// so each existing Navigator.push gets it without being edited).
///
/// A page slides a short distance in the reading direction and fades in; the
/// page beneath recedes slightly. Short and quiet: it confirms «you went
/// deeper», nothing more. With reduced motion it is a plain fade.
class MqTransitionsBuilder extends PageTransitionsBuilder {
  const MqTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: MqMotion.enter, reverseCurve: Curves.easeIn);
    if (MediaQuery.of(context).disableAnimations) {
      return FadeTransition(opacity: curved, child: child);
    }
    final dir = Directionality.of(context);
    final slide = Tween<Offset>(begin: const Offset(0.07, 0), end: Offset.zero)
        .animate(curved);
    final recede = Tween<Offset>(begin: Offset.zero, end: const Offset(-0.03, 0))
        .animate(CurvedAnimation(
            parent: secondaryAnimation, curve: MqMotion.enter));
    return SlideTransition(
      position: recede,
      textDirection: dir,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: slide,
          textDirection: dir,
          child: child,
        ),
      ),
    );
  }
}

/// Fades and lifts its child in once, after [index] * 45 ms. Lists use it so
/// content arrives in order instead of all at once.
class MqReveal extends StatefulWidget {
  const MqReveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<MqReveal> createState() => _MqRevealState();
}

class _MqRevealState extends State<MqReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: MqMotion.base);
    final delay = Duration(milliseconds: 45 * widget.index.clamp(0, 8));
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    final curved = CurvedAnimation(parent: _c, curve: MqMotion.enter);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Switches between the children of a tab bar: the shown page eases in when
/// the index changes, while every page keeps its state (IndexedStack).
class MqTabStack extends StatefulWidget {
  const MqTabStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<MqTabStack> createState() => _MqTabStackState();
}

class _MqTabStackState extends State<MqTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: MqMotion.base, value: 1);
  }

  @override
  void didUpdateWidget(MqTabStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = IndexedStack(index: widget.index, children: widget.children);
    if (MediaQuery.of(context).disableAnimations) return stack;
    final curved = CurvedAnimation(parent: _c, curve: MqMotion.enter);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(curved),
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 10 * (1 - curved.value)),
          child: child,
        ),
        child: stack,
      ),
    );
  }
}
