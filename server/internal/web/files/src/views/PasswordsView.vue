<template>
  <div class="page-container">
    <div class="page-title-bar">
      <h2>密码记录</h2>
    </div>

    <div class="passwords-view">
      <aside class="list-pane">
        <el-card shadow="never" class="list-card">
          <div class="list-header">
            <el-input v-model="keyword" placeholder="搜索平台或账号" :prefix-icon="Search" clearable size="default" />
            <el-select v-model="categoryFilter" size="default" class="cat-filter">
              <el-option label="全部分类" value="" />
              <el-option label="社交" value="social" />
              <el-option label="办公" value="office" />
              <el-option label="金融" value="finance" />
              <el-option label="自定义" value="custom" />
            </el-select>
            <el-button type="primary" :icon="Plus" @click="onNew">新建密码</el-button>
          </div>

          <el-scrollbar class="password-scroll" v-loading="store.loading">
            <el-empty v-if="!store.list.length" description="还没有密码记录，点击「新建密码」开始" :image-size="80" />
            <div
              v-for="p in filteredList"
              :key="p.id"
              class="password-item"
              :class="{ active: p.id === currentId }"
              @click="onSelect(p.id)"
            >
              <div class="item-avatar" :class="`cat-${p.category}`">
                {{ avatarChar(p.platform) }}
              </div>
              <div class="item-main">
                <div class="platform">{{ p.platform }}</div>
                <div class="account">{{ p.account }}</div>
              </div>
              <div class="item-meta">
                <el-tag size="small" :type="categoryTagType(p.category)" effect="light" round>
                  {{ categoryLabel(p.category) }}
                </el-tag>
              </div>
            </div>
          </el-scrollbar>
        </el-card>
      </aside>

      <section class="form-pane">
        <PasswordForm
          v-if="store.current || mode === 'create'"
          :password="store.current"
          @saved="onSaved"
          @cancel="onCancel"
          @delete="onDeleted"
        />
        <el-card v-else shadow="never" class="empty-pane">
          <el-empty description="点击「新建密码」或在左侧选择一条记录开始录入" :image-size="120">
            <template #description>
              <p style="margin: 0">点击「新建密码」或在左侧选择一条记录开始录入</p>
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
import PasswordForm from '@/components/PasswordForm.vue'
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

function categoryTagType(v: string): 'primary' | 'success' | 'warning' | 'danger' | 'info' | undefined {
  return ({ social: undefined, office: 'success', finance: 'warning', custom: 'info' } as Record<string, 'primary' | 'success' | 'warning' | 'danger' | 'info' | undefined>)[v]
}

function avatarChar(s: string): string {
  return (s || '?').charAt(0).toUpperCase()
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
  grid-template-columns: 340px 1fr;
  gap: 16px;
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
.password-scroll {
  height: calc(100vh - 280px);
  min-height: 300px;
}
.password-item {
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
.item-avatar {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  color: #fff;
  font-size: 16px;
  flex-shrink: 0;
}
.item-avatar.cat-social {
  background: linear-gradient(135deg, #007aff, #4d9bff);
}
.item-avatar.cat-office {
  background: linear-gradient(135deg, #34c759, #5dd87a);
}
.item-avatar.cat-finance {
  background: linear-gradient(135deg, #ff9500, #ffb14d);
}
.item-avatar.cat-custom {
  background: linear-gradient(135deg, #8e8e93, #aeaeb2);
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
  color: #1f2329;
}
.account {
  font-size: 12px;
  color: #8e8e93;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  margin-top: 2px;
}
.item-meta {
  flex-shrink: 0;
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
