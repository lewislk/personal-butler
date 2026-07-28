import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { router } from './router'
import 'element-plus/theme-chalk/dark/css-vars.css'
// JS API（ElMessage / ElMessageBox / ElLoading / ElNotification）的样式
// 不会被 unplugin-vue-components 自动注入，必须手动引入，否则提示框会失去 fixed 定位
import 'element-plus/theme-chalk/el-message.css'
import 'element-plus/theme-chalk/el-message-box.css'
import 'element-plus/theme-chalk/el-loading.css'
import 'element-plus/theme-chalk/el-notification.css'
import './styles/global.scss'

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.mount('#app')
