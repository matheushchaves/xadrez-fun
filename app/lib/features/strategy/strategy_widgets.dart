import 'package:flutter/material.dart';

/// Cartão de seção com título, ícone e conteúdo — usado por cada
/// analisador na aba Estratégia.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final String icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$icon $title', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Lista de itens com marcador, ou um texto de estado vazio quando [items]
/// está vazia.
class BulletList extends StatelessWidget {
  const BulletList({super.key, required this.items, this.emptyText});

  final List<String> items;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        emptyText ?? 'Nenhum',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '• $item',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
