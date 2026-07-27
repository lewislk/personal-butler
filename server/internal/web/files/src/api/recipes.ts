import { http } from './http'
import type { Recipe, RecipeInput } from '@/types/recipe'

export const recipeApi = {
  list: () => http.get<Recipe[]>('/api/recipes'),
  get: (id: string) => http.get<Recipe>(`/api/recipes/${encodeURIComponent(id)}`),
  create: (input: RecipeInput) => http.post<{ id: string }>('/api/recipes', input),
  update: (id: string, input: RecipeInput) =>
    http.put<void>(`/api/recipes/${encodeURIComponent(id)}`, input),
  remove: (id: string) => http.delete<void>(`/api/recipes/${encodeURIComponent(id)}`),
}
