<template>
  <div class="ingredient-editor">
    <div v-for="(ing, idx) in ingredients" :key="idx" class="ing-row">
      <el-input v-model="ing.name" placeholder="食材名" class="col-name" />
      <el-input v-model="ing.amount" placeholder="用量" class="col-amount" />
      <el-input-number v-model="ing.order" :min="0" :controls="false" placeholder="顺序" class="col-order" />
      <el-button type="danger" :icon="Delete" circle size="small" @click="remove(idx)" />
    </div>
    <el-button size="small" @click="add">+ 添加食材</el-button>
    <p class="hint">行顺序由「顺序」数字控制，相等时按录入顺序。空行会被自动跳过。</p>
  </div>
</template>

<script setup lang="ts">
import { Delete } from '@element-plus/icons-vue'
import type { RecipeIngredient } from '@/types/recipe'

const props = defineProps<{ modelValue: Array<Omit<RecipeIngredient, 'id'> & { id?: string }> }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: Array<Omit<RecipeIngredient, 'id'> & { id?: string }>): void }>()

// 模板里用 ingredients 别名引用 props.modelValue（数组引用一致，mutate 同一对象）
const ingredients = props.modelValue

// 直接 mutate props.modelValue（Pinia store 中也是数组引用），同时 emit 触发响应
function add() {
  ingredients.push({ id: undefined, name: '', amount: '', order: ingredients.length })
  emit('update:modelValue', ingredients)
}
function remove(idx: number) {
  ingredients.splice(idx, 1)
  emit('update:modelValue', ingredients)
}
</script>

<style scoped lang="scss">
.ing-row {
  display: grid;
  grid-template-columns: 2fr 2fr 1fr auto;
  gap: 8px;
  margin-bottom: 8px;
  align-items: center;
}
.hint {
  color: #8e8e93;
  font-size: 12px;
  margin: 8px 0 0;
}
</style>
