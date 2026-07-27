<template>
  <div class="passwords-view">
    <aside class="list-pane">
      <div class="list-header">
        <el-input v-model="keyword" placeholder="搜索平台或账号" :prefix-icon="Search" clearable size="small" />
        <el-select v-model="categoryFilter" size="small" class="cat-filter">
          <el-option label="全部分类" value="" />
          <el-option label="社交" value="social" />
          <el-option label="办公" value="office" />
          <el-option label="金融" value="finance" />
          <el-option label="自定义" value="custom" />
        </el-select>
        <el-button type="primary" size="small" @click="onNew">+ 新建密码</el-button>
      </div>
      <div class="password-list" v-loading="store.loading">
        <p v-if="!store.list.length" class="empty">还没有密码记录，点击「+ 新建密码」开始</p>
        <div
          v-for="p in filteredList"
          :key="p.id"
          class="password-item"
          :class="{ active: p.id === currentId }"
          @click="onSelect(p.id)"
        >
          <div class="item-main">
            <div class="platform">{{ p.platform }}</div>
            <div class="account">{{ p.account }}</div>
          </div>
          <div class="item-meta">
            <el-tag size="small" :type="categoryTagType(p.category)">{{ categoryLabel(p.category) }}</el-tag>
            <span v-if="p.typeText" class="type-text">{{ p.typeText }}</span>
          </div>
        </div>
      </div>
    </aside>

    <section class="form-pane">
      <PasswordForm
        v-if="store.current || mode === 'create'"
        :password="store.current"
        @saved="onSaved"
        @cancel="onCancel"
        @delete="onDeleted"
      />
      <EmptyState v-else emoji="👈" title="点击「+ 新建密码」或在左侧选择一条记录开始录入" hint="保存后，iOS 端走「局域网同步 → 下载」即可恢复到本地" />
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Search } from '@element-plus/icons-vue'
import PasswordForm from '@/components/PasswordForm.vue'
import EmptyState from '@/components/EmptyState.vue'
import { usePasswordsStore, passwordErrorMsg } from '@/stores/passwords'
import { useToast } from '@/composables/useToast'

const store = usePasswordsStore()
const toast = useToast()

const keyword = ref('')
const categoryFilter = ref('')
const currentId = ref<string | null>(null)
const mode = ref<'view' | 'create'>('view')

const filteredList = computed(() =>
  store.list.filter((p) => {
    const kw = keyword.value.trim().toLowerCase()
    const matchKw = !kw || p.platform.toLowerCase().includes(kw) || p.account.toLowerCase().includes(kw)
    const matchCat = !categoryFilter.value || p.category === categoryFilter.value
    return matchKw && matchCat
  })
)

onMounted(async () => {
  try {
    await store.fetchList()
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  }
})

function categoryLabel(v: string): string {
  return ({ social: '社交', office: '办公', finance: '金融', custom: '自定义' } as Record<string, string>)[v] || v
}

function categoryTagType(v: string): '' | 'success' | 'warning' | 'danger' | 'info' {
  return ({ social: '', office: 'success', finance: 'warning', custom: 'info' } as Record<string, '' | 'success' | 'warning' | 'danger' | 'info'>)[v] || ''
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
    toast.showError(err, passwordErrorMsg(err))
  }
}

async function onSaved(id: string) {
  currentId.value = id
  mode.value = 'view'
  try {
    await store.fetchList()
    await store.fetchOne(id)
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  }
}

function onCancel() {
  store.clearCurrent()
  mode.value = 'view'
}

async function onDeleted() {
  currentId.value = null
  store.clearCurrent()
  mode.value = 'view'
  try {
    await store.fetchList()
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  }
}
</script>

<style scoped lang="scss">
.passwords-view {
  display: grid;
  grid-template-columns: 320px 1fr;
  gap: 16px;
  padding: 16px 24px;
  align-items: start;
}
@media (max-width: 960px) {
  .passwords-view {
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
.password-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.password-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  background: #fff;
  border: 1px solid #e5e5ea;
  border-radius: 8px;
  padding: 10px 12px;
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
}
.password-item:hover {
  border-color: #007aff;
}
.password-item.active {
  background: #f0f8ff;
  border-color: #007aff;
}
.item-main {
  flex: 1;
  overflow: hidden;
}
.platform {
  font-weight: 500;
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.account {
  font-size: 12px;
  color: #8e8e93;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.item-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
  flex-shrink: 0;
}
.type-text {
  font-size: 11px;
  color: #aeaeb2;
}
.empty {
  color: #8e8e93;
  text-align: center;
  padding: 24px;
  font-size: 13px;
}
</style>
