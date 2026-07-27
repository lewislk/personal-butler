<template>
  <el-card class="recipe-form-card">
    <el-form label-position="top" @submit.prevent="onSubmit">
      <el-form-item label="名称" required>
        <el-input v-model="form.name" placeholder="番茄炒蛋" required />
      </el-form-item>

      <el-row :gutter="12">
        <el-col :span="8">
          <el-form-item label="Emoji 图标">
            <el-input v-model="form.emoji" maxlength="8" placeholder="🍲" />
          </el-form-item>
        </el-col>
        <el-col :span="8">
          <el-form-item label="难度">
            <el-select v-model="form.difficulty">
              <el-option label="简单" value="easy" />
              <el-option label="中等" value="medium" />
              <el-option label="进阶" value="hard" />
            </el-select>
          </el-form-item>
        </el-col>
        <el-col :span="8">
          <el-form-item label="分类">
            <el-select v-model="form.category">
              <el-option label="家常菜" value="home" />
              <el-option label="面食" value="noodle" />
              <el-option label="汤羹" value="soup" />
              <el-option label="甜品" value="dessert" />
            </el-select>
          </el-form-item>
        </el-col>
      </el-row>

      <el-form-item label="分钟">
        <el-input-number v-model="form.minutes" :min="1" />
      </el-form-item>

      <el-form-item label="图片图标（可选，JPEG/PNG ≤ 512px）">
        <ImagePicker v-model="form.iconImageBase64" />
      </el-form-item>

      <el-form-item label="食材">
        <IngredientEditor v-model="form.ingredients" />
      </el-form-item>

      <el-form-item label="步骤（每行一条）">
        <el-input v-model="form.steps" type="textarea" :rows="6" placeholder="1. 鸡蛋打散加少许盐&#10;2. 番茄切块" />
      </el-form-item>

      <el-form-item label="小贴士">
        <el-input v-model="form.tips" type="textarea" :rows="3" placeholder="可选，例如：盐别放多" />
      </el-form-item>

      <el-collapse>
        <el-collapse-item title="旧版食材文本（迁移用，一般留空）" name="legacy">
          <el-input v-model="form.ingredientsLegacyRaw" type="textarea" :rows="2" placeholder="兼容字段，新数据请用上面的食材列表" />
        </el-collapse-item>
      </el-collapse>

      <div class="form-actions">
        <el-button type="primary" :loading="saving" @click="onSubmit">保存</el-button>
        <el-button @click="onCancel">取消</el-button>
        <el-button v-if="isEdit" type="danger" @click="onDelete">删除</el-button>
      </div>
    </el-form>
  </el-card>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import ImagePicker from './ImagePicker.vue'
import IngredientEditor from './IngredientEditor.vue'
import { useRecipesStore, recipeErrorMsg } from '@/stores/recipes'
import { useToast } from '@/composables/useToast'
import type { Recipe, RecipeInput, RecipeIngredient } from '@/types/recipe'

const props = defineProps<{ recipe: Recipe | null }>()
const emit = defineEmits<{ (e: 'saved', id: string): void; (e: 'cancel'): void; (e: 'delete'): void }>()

const store = useRecipesStore()
const toast = useToast()
const saving = ref(false)

const isEdit = computed(() => !!props.recipe)

interface FormState {
  id?: string
  name: string
  emoji: string
  difficulty: string
  minutes: number
  category: string
  steps: string
  tips: string
  ingredientsLegacyRaw: string
  iconImageBase64: string | null
  ingredients: Array<Omit<RecipeIngredient, 'id'> & { id?: string }>
}

function emptyForm(): FormState {
  return {
    name: '',
    emoji: '🍲',
    difficulty: 'easy',
    minutes: 30,
    category: 'home',
    steps: '',
    tips: '',
    ingredientsLegacyRaw: '',
    iconImageBase64: null,
    ingredients: [],
  }
}

const form = reactive<FormState>(emptyForm())

watch(
  () => props.recipe,
  (r) => {
    Object.assign(form, emptyForm())
    if (r) {
      form.id = r.id
      form.name = r.name
      form.emoji = r.emoji || '🍲'
      form.difficulty = r.difficulty || 'easy'
      form.minutes = r.minutes || 30
      form.category = r.category || 'home'
      form.steps = r.steps || ''
      form.tips = r.tips || ''
      form.ingredientsLegacyRaw = r.ingredientsLegacyRaw || ''
      form.iconImageBase64 = r.iconImageBase64 || null
      form.ingredients = (r.ingredients || []).map((i) => ({ ...i }))
    }
  },
  { immediate: true }
)

async function onSubmit() {
  if (!form.name.trim()) {
    toast.warn('请填写名称')
    return
  }
  saving.value = true
  try {
    const payload: RecipeInput = {
      id: form.id,
      name: form.name.trim(),
      emoji: form.emoji.trim() || '🍲',
      difficulty: form.difficulty,
      minutes: form.minutes,
      category: form.category,
      steps: form.steps,
      tips: form.tips,
      ingredientsLegacyRaw: form.ingredientsLegacyRaw,
      iconImageBase64: form.iconImageBase64,
      ingredients: form.ingredients
        .filter((i) => i.name.trim() || i.amount.trim())
        .map((i) => ({ id: i.id, name: i.name.trim(), amount: i.amount.trim(), order: i.order })),
    }
    let savedId: string
    if (payload.id) {
      await store.update(payload.id, payload)
      savedId = payload.id
    } else {
      savedId = await store.create(payload)
    }
    toast.success('已保存')
    emit('saved', savedId)
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  } finally {
    saving.value = false
  }
}

function onCancel() {
  emit('cancel')
}

async function onDelete() {
  if (!form.id) return
  if (!(await toast.confirm('确认删除该菜谱？该操作不可撤销。', '删除确认'))) return
  try {
    await store.remove(form.id)
    toast.success('已删除')
    emit('delete')
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  }
}
</script>

<style scoped lang="scss">
.form-actions {
  display: flex;
  gap: 8px;
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid #e5e5ea;
}
</style>
