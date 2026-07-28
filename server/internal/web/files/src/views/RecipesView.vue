<template>
  <div class="page-container">
    <div class="page-title-bar">
      <h2>烹饪管理</h2>
    </div>

    <div class="recipes-view">
      <aside class="list-pane">
        <el-card shadow="never" class="list-card">
          <div class="list-header">
            <el-input v-model="keyword" placeholder="搜索菜谱名" :prefix-icon="Search" clearable size="default" />
            <el-select v-model="categoryFilter" size="default" class="cat-filter">
              <el-option label="全部分类" value="" />
              <el-option label="家常菜" value="home" />
              <el-option label="面食" value="noodle" />
              <el-option label="汤羹" value="soup" />
              <el-option label="甜品" value="dessert" />
            </el-select>
            <el-button type="primary" :icon="Plus" @click="onNew">新建菜谱</el-button>
          </div>

          <el-scrollbar class="recipe-scroll" v-loading="store.loading">
            <el-empty v-if="!store.list.length" description="还没有菜谱，点击「新建菜谱」开始" :image-size="80" />
            <div
              v-for="r in filteredList"
              :key="r.id"
              class="recipe-item"
              :class="{ active: r.id === currentId }"
              @click="onSelect(r.id)"
            >
              <div class="item-emoji">{{ r.emoji || '🍲' }}</div>
              <div class="item-main">
                <div class="item-name">{{ r.name }}</div>
                <div class="item-meta">
                  <el-tag size="small" effect="plain" round>{{ difficultyLabel(r.difficulty) }}</el-tag>
                  <span class="minutes">{{ r.minutes }} 分钟</span>
                </div>
              </div>
            </div>
          </el-scrollbar>
        </el-card>
      </aside>

      <section class="form-pane">
        <RecipeForm
          v-if="store.current || mode === 'create'"
          :recipe="store.current"
          @saved="onSaved"
          @cancel="onCancel"
          @delete="onDeleted"
        />
        <el-card v-else shadow="never" class="empty-pane">
          <el-empty description="点击「新建菜谱」或在左侧选择一条菜谱开始录入" :image-size="120">
            <template #description>
              <p style="margin: 0">点击「新建菜谱」或在左侧选择一条菜谱开始录入</p>
              <p style="margin: 4px 0 0; color: #8e8e93; font-size: 12px">保存后，iOS 端走「局域网同步 → 下载」即可恢复到本地</p>
            </template>
          </el-empty>
        </el-card>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Plus, Search } from '@element-plus/icons-vue'
import RecipeForm from '@/components/RecipeForm.vue'
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
  grid-template-columns: 340px 1fr;
  gap: 16px;
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
.list-card {
  :deep(.el-card__body) {
    padding: 12px;
  }
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
.recipe-scroll {
  height: calc(100vh - 280px);
  min-height: 300px;
}
.recipe-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.15s ease;
  margin-bottom: 4px;

  &:hover {
    background: #f5f7fa;
  }
  &.active {
    background: linear-gradient(135deg, #e0efff 0%, #f0f8ff 100%);
    box-shadow: inset 3px 0 0 #007aff;
  }
}
.item-emoji {
  font-size: 22px;
  flex-shrink: 0;
  width: 32px;
  text-align: center;
}
.item-main {
  flex: 1;
  overflow: hidden;
}
.item-name {
  font-weight: 500;
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #1f2329;
}
.item-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 4px;
}
.minutes {
  font-size: 11px;
  color: #8e8e93;
}
.empty-pane {
  min-height: 400px;
  display: flex;
  align-items: center;
  justify-content: center;

  :deep(.el-card__body) {
    width: 100%;
  }
}
</style>
