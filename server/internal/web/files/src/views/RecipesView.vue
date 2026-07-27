<template>
  <div class="recipes-view">
    <aside class="list-pane">
      <div class="list-header">
        <el-input v-model="keyword" placeholder="搜索菜谱名" :prefix-icon="Search" clearable size="small" />
        <el-select v-model="categoryFilter" size="small" class="cat-filter">
          <el-option label="全部分类" value="" />
          <el-option label="家常菜" value="home" />
          <el-option label="面食" value="noodle" />
          <el-option label="汤羹" value="soup" />
          <el-option label="甜品" value="dessert" />
        </el-select>
        <el-button type="primary" size="small" @click="onNew">+ 新建</el-button>
      </div>
      <div class="recipe-list" v-loading="store.loading">
        <p v-if="!store.list.length" class="empty">还没有菜谱，点击「+ 新建」开始</p>
        <div
          v-for="r in filteredList"
          :key="r.id"
          class="recipe-item"
          :class="{ active: r.id === currentId }"
          @click="onSelect(r.id)"
        >
          <span class="emoji">{{ r.emoji || '🍲' }}</span>
          <span class="name">{{ r.name }}</span>
          <span class="meta">{{ r.minutes }}min · {{ difficultyLabel(r.difficulty) }}</span>
        </div>
      </div>
    </aside>

    <section class="form-pane">
      <RecipeForm
        v-if="store.current || mode === 'create'"
        :recipe="store.current"
        @saved="onSaved"
        @cancel="onCancel"
        @delete="onDeleted"
      />
      <EmptyState v-else emoji="👈" title="点击「+ 新建」或在左侧选择一条菜谱开始录入" hint="保存后，iOS 端走「局域网同步 → 下载」即可恢复到本地" />
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Search } from '@element-plus/icons-vue'
import RecipeForm from '@/components/RecipeForm.vue'
import EmptyState from '@/components/EmptyState.vue'
import { useRecipesStore, recipeErrorMsg } from '@/stores/recipes'
import { useToast } from '@/composables/useToast'

const store = useRecipesStore()
const toast = useToast()

const keyword = ref('')
const categoryFilter = ref('')
const currentId = ref<string | null>(null)
const mode = ref<'view' | 'create'>('view')

const filteredList = computed(() =>
  store.list.filter((r) => {
    const kw = keyword.value.trim().toLowerCase()
    const matchKw = !kw || r.name.toLowerCase().includes(kw)
    const matchCat = !categoryFilter.value || r.category === categoryFilter.value
    return matchKw && matchCat
  })
)

onMounted(async () => {
  try {
    await store.fetchList()
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  }
})

function difficultyLabel(v: string): string {
  return ({ easy: '简单', medium: '中等', hard: '进阶' } as Record<string, string>)[v] || v
}

function onNew() {
  currentId.value = null
  store.clearCurrent()
  mode.value = 'create'
}

async function onSelect(id: string) {
  currentId.value = id
  mode.value = 'view'
  try {
    await store.fetchOne(id)
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  }
}

async function onSaved(id: string) {
  currentId.value = id
  mode.value = 'view'
  await store.fetchList()
  await store.fetchOne(id)
}

function onCancel() {
  store.clearCurrent()
  mode.value = 'view'
}

async function onDeleted() {
  currentId.value = null
  store.clearCurrent()
  mode.value = 'view'
  await store.fetchList()
}
</script>

<style scoped lang="scss">
.recipes-view {
  display: grid;
  grid-template-columns: 320px 1fr;
  gap: 16px;
  padding: 16px 24px;
  align-items: start;
}
@media (max-width: 960px) {
  .recipes-view {
    grid-template-columns: 1fr;
  }
}
.list-pane {
  position: sticky;
  top: 72px;
}
.list-header {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 12px;
}
.cat-filter {
  width: 100%;
}
.recipe-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.recipe-item {
  display: flex;
  align-items: center;
  gap: 10px;
  background: #fff;
  border: 1px solid #e5e5ea;
  border-radius: 8px;
  padding: 10px 12px;
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
}
.recipe-item:hover {
  border-color: #007aff;
}
.recipe-item.active {
  background: #f0f8ff;
  border-color: #007aff;
}
.recipe-item .emoji {
  font-size: 18px;
  flex-shrink: 0;
}
.recipe-item .name {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.recipe-item .meta {
  font-size: 11px;
  color: #8e8e93;
  flex-shrink: 0;
}
.empty {
  color: #8e8e93;
  text-align: center;
  padding: 24px;
  font-size: 13px;
}
</style>
