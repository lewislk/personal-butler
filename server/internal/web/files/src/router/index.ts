import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router'

const routes: RouteRecordRaw[] = [
  { path: '/', name: 'home', component: () => import('@/views/HomeView.vue'), meta: { title: '总览' } },
  { path: '/recipes', name: 'recipes', component: () => import('@/views/RecipesView.vue'), meta: { title: '烹饪管理' } },
  { path: '/passwords', name: 'passwords', component: () => import('@/views/PasswordsView.vue'), meta: { title: '密码记录' } },
  { path: '/settings', name: 'settings', component: () => import('@/views/SettingsView.vue'), meta: { title: '配置' } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export const router = createRouter({
  history: createWebHashHistory(),
  routes,
})
