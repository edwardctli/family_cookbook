export type TabKey = 'recipes' | 'activity' | 'shopping' | 'profile'

export type SessionState =
  | { status: 'missing-config' }
  | { status: 'loading' }
  | { status: 'signed-out' }
  | {
      status: 'signed-in'
      email: string
      userId: string
      displayName: string
    }

export interface CookbookSnapshot {
  title: string
  ownerName: string
  updatedAt: string
  recipes: RecipeSnapshot[]
  shoppingItems: ShoppingListItemSnapshot[]
}

export interface RecipeSnapshot {
  id: string
  title: string
  summary: string
  familyOwner: string
  isFavorite: boolean
  tags: string[]
  sortOrder: number
  createdAt: string
  updatedAt: string
  ingredients: IngredientSnapshot[]
  steps: RecipeStepSnapshot[]
  logs: CookLogSnapshot[]
}

export interface IngredientSnapshot {
  id: string
  amount: string
  name: string
  sortOrder: number
}

export interface RecipeStepSnapshot {
  id: string
  title: string
  instruction: string
  sortOrder: number
}

export interface CookLogSnapshot {
  id: string
  cookedOn: string
  cookName: string
  rating: number
  mood: string
  tweakSummary: string
  notes: string
  nextTimeNote: string
  createdAt: string
  updatedAt: string
  photos: CookPhotoSnapshot[]
  observations: StepObservationSnapshot[]
}

export interface CookPhotoSnapshot {
  id: string
  stage: string
  caption: string
  imageData?: string | null
  sortOrder: number
}

export interface StepObservationSnapshot {
  id: string
  stepTitle: string
  note: string
  sortOrder: number
}

export interface ShoppingListItemSnapshot {
  id: string
  itemName: string
  amountText: string
  sourceRecipeTitle: string
  note: string
  isChecked: boolean
  sortOrder: number
  createdAt: string
  updatedAt: string
}
