import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/category.dart';
import 'repository_providers.dart';
import 'stats_providers.dart';

class CategoriesController extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() {
    return ref.watch(categoryRepositoryProvider).list(includeArchived: true);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(categoryRepositoryProvider).list(includeArchived: true),
    );
  }

  Future<Category> create({
    required String name,
    required int color,
    required String icon,
    required double weight,
  }) async {
    final category = await ref
        .read(categoryRepositoryProvider)
        .create(name: name, color: color, icon: icon, weight: weight);
    await refresh();
    invalidateStats(ref);
    return category;
  }

  Future<void> updateCategory(Category category) async {
    await ref.read(categoryRepositoryProvider).update(category);
    await refresh();
    invalidateStats(ref);
  }

  Future<void> setArchived(Category category, bool archived) async {
    await ref
        .read(categoryRepositoryProvider)
        .setArchived(category.id, archived);
    await refresh();
    invalidateStats(ref);
  }

  Future<void> deleteIfEmpty(Category category) async {
    await ref.read(categoryRepositoryProvider).deleteIfEmpty(category.id);
    await refresh();
    invalidateStats(ref);
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesController, List<Category>>(
      CategoriesController.new,
    );
