// 与 dto.SyncRecipeDTO / SyncIngredientDTO 对齐
export interface RecipeIngredient {
  id: string
  name: string
  amount: string
  order: number
}

export interface Recipe {
  id: string
  name: string
  emoji: string
  difficulty: string  // easy / medium / hard
  minutes: number
  category: string    // home / noodle / soup / dessert
  ingredientsLegacyRaw: string
  ingredients: RecipeIngredient[]
  steps: string
  tips: string
  iconImageBase64?: string | null
  isDemo?: boolean | null
}

// POST/PUT 提交结构。id 创建时省略，编辑时必填
export interface RecipeInput {
  id?: string
  name: string
  emoji: string
  difficulty: string
  minutes: number
  category: string
  steps: string
  tips: string
  ingredientsLegacyRaw: string
  iconImageBase64?: string | null
  ingredients: Array<{
    id?: string
    name: string
    amount: string
    order: number
  }>
}
