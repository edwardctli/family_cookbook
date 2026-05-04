import { useEffect, useMemo, useState } from 'react'
import type { ChangeEvent, FormEvent, PointerEvent, ReactNode } from 'react'
import './App.css'
import { isSupabaseConfigured, supabase } from './lib/supabase'
import type {
  CookbookSnapshot,
  CookLogSnapshot,
  CookPhotoSnapshot,
  RecipeSnapshot,
  RecipeStepSnapshot,
  SessionState,
  ShoppingListItemSnapshot,
  TabKey,
} from './types'

const SHARED_COOKBOOK_SLUG = 'family-cookbook'
const OFFLINE_COOKBOOK_KEY = 'family-cookbook:lastSnapshot'
const PENDING_COOKBOOK_KEY = 'family-cookbook:pendingSnapshot'
const UPDATE_APPLIED_KEY = 'family-cookbook:updateApplied'
const SNAPSHOT_DB_NAME = 'family-cookbook-snapshots'
const SNAPSHOT_STORE_NAME = 'snapshots'
const APP_VERSION = 'web parity 3'
const EMPTY_RECIPES: RecipeSnapshot[] = []

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

type RecipeFilter = 'all' | 'favorites' | 'cooked'
type RecipeSort = 'title' | 'owner' | 'recent'

type RecipeDraft = {
  title: string
  summary: string
  familyOwner: string
  isFavorite: boolean
  tagsText: string
  ingredients: IngredientDraft[]
  steps: StepDraft[]
}

type IngredientDraft = {
  id: string
  amount: string
  unit: string
  name: string
}

type StepDraft = {
  id: string
  title: string
  instruction: string
}

type LogDraft = {
  cookedOn: string
  cookName: string
  rating: number
  mood: string
  tweakSummary: string
  notes: string
  nextTimeNote: string
  observations: ObservationDraft[]
  photos: PhotoDraft[]
}

type ObservationDraft = {
  id: string
  stepTitle: string
  note: string
}

type PhotoDraft = {
  id: string
  stage: string
  caption: string
  imageData: string
}

type ScaleState = {
  recipeId: string
  factor: number
  source: 'multiplier' | 'ingredient'
}

type ImportState = {
  isOpen: boolean
  url: string
  isLoading: boolean
  message: string | null
  importedRecipe: RecipeSnapshot | null
}

type DataNotice = {
  kind: 'success' | 'error'
  text: string
}

type PendingConflict = {
  message: string
  localSnapshot: CookbookSnapshot
  remoteSnapshot: CookbookSnapshot
  successMessage: string
}

type SelectedLog = {
  recipeId: string
  recipeTitle: string
  log: CookLogSnapshot
}

type SwipeAction = {
  id: string
  leftLabel?: string
  rightLabel?: string
  onLeft?: () => void
  onRight?: () => void
}

type SwipeFeedback = {
  id: string
  offset: number
  label: string
}

type ServiceWorkerSyncRegistration = ServiceWorkerRegistration & {
  sync?: {
    register: (tag: string) => Promise<void>
  }
}

function App() {
  const [sessionState, setSessionState] = useState<SessionState>({
    status: isSupabaseConfigured ? 'loading' : 'missing-config',
  })
  const [authMode, setAuthMode] = useState<'sign-in' | 'sign-up'>('sign-in')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [invitePasscode, setInvitePasscode] = useState('')
  const [authMessage, setAuthMessage] = useState<string | null>(null)
  const [displayNameDraft, setDisplayNameDraft] = useState('')
  const [isSavingProfile, setIsSavingProfile] = useState(false)
  const [cookbook, setCookbook] = useState<CookbookSnapshot | null>(() => loadPendingCookbook() ?? loadCachedCookbook())
  const [isRefreshing, setIsRefreshing] = useState(false)
  const [isSavingCookbook, setIsSavingCookbook] = useState(false)
  const [dataNotice, setDataNotice] = useState<DataNotice | null>(() => {
    if (localStorage.getItem(UPDATE_APPLIED_KEY)) {
      localStorage.removeItem(UPDATE_APPLIED_KEY)
      return { kind: 'success', text: `Updated to ${APP_VERSION}. Offline shell is fresh.` }
    }

    return null
  })
  const [activeTab, setActiveTab] = useState<TabKey>(() => parseRoute().tab)
  const [selectedRecipeId, setSelectedRecipeId] = useState<string | null>(() => parseRoute().recipeId)
  const [recipeSearchText, setRecipeSearchText] = useState('')
  const [recipeFilter, setRecipeFilter] = useState<RecipeFilter>('all')
  const [recipeSort, setRecipeSort] = useState<RecipeSort>('title')
  const [recipeViewMode, setRecipeViewMode] = useState<'cards' | 'list'>('cards')
  const [recipeOptionsMenu, setRecipeOptionsMenu] = useState<'filter' | 'sort' | null>(null)
  const [editingRecipeId, setEditingRecipeId] = useState<string | null>(null)
  const [recipeDraft, setRecipeDraft] = useState<RecipeDraft | null>(null)
  const [loggingRecipeId, setLoggingRecipeId] = useState<string | null>(null)
  const [logDraft, setLogDraft] = useState<LogDraft | null>(null)
  const [selectedLog, setSelectedLog] = useState<SelectedLog | null>(null)
  const [shoppingDraft, setShoppingDraft] = useState({ itemName: '', amountText: '', note: '' })
  const [scaleState, setScaleState] = useState<ScaleState | null>(null)
  const [pendingConflict, setPendingConflict] = useState<PendingConflict | null>(null)
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null)
  const [lastSyncDirection, setLastSyncDirection] = useState<'pull' | 'push' | null>(null)
  const [hasPendingLocalChanges, setHasPendingLocalChanges] = useState(() => Boolean(loadPendingCookbook()))
  const [isOnline, setIsOnline] = useState(() => (typeof navigator === 'undefined' ? true : navigator.onLine))
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent | null>(null)
  const [updateAvailable, setUpdateAvailable] = useState(false)
  const [isPulling, setIsPulling] = useState(false)
  const [pullDistance, setPullDistance] = useState(0)
  const [swipeFeedback, setSwipeFeedback] = useState<SwipeFeedback | null>(null)
  const [syncWakeupSource, setSyncWakeupSource] = useState<string | null>(null)
  const [importState, setImportState] = useState<ImportState>({
    isOpen: false,
    url: '',
    isLoading: false,
    message: null,
    importedRecipe: null,
  })

  useEffect(() => {
    if (!supabase) {
      return
    }

    let isCancelled = false
    const client = supabase

    async function bootstrap() {
      const { data, error } = await client.auth.getSession()

      if (isCancelled) {
        return
      }

      if (error) {
        setSessionState({ status: 'signed-out' })
        setAuthMessage(error.message)
        return
      }

      const session = data.session
      if (!session?.user) {
        setSessionState({ status: 'signed-out' })
        return
      }

      await adoptSignedInSession(session.user.email ?? 'Signed In', session.user.id)
    }

    void bootstrap()

    const {
      data: { subscription },
    } = client.auth.onAuthStateChange((_event, session) => {
      if (!session?.user) {
        setSessionState({ status: 'signed-out' })
        setCookbook(null)
        setSelectedRecipeId(null)
        setDisplayNameDraft('')
        return
      }

      void adoptSignedInSession(session.user.email ?? 'Signed In', session.user.id)
    })

    return () => {
      isCancelled = true
      subscription.unsubscribe()
    }
    // The auth listener is registered once; session adoption passes the owner fallback needed during bootstrap.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    const handleOnline = () => setIsOnline(true)
    const handleOffline = () => setIsOnline(false)
    const handleServiceWorkerUpdate = () => setUpdateAvailable(true)
    const handleServiceWorkerMessage = (event: MessageEvent) => {
      if (event.data?.type === 'SYNC_PENDING_COOKBOOK') {
        setSyncWakeupSource(event.data.source ?? 'service worker')
        void pushPendingSnapshotIfNeeded()
      }
    }
    const handleBeforeInstallPrompt = (event: Event) => {
      event.preventDefault()
      setInstallPrompt(event as BeforeInstallPromptEvent)
    }

    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
    window.addEventListener('family-cookbook-sw-update', handleServiceWorkerUpdate)
    navigator.serviceWorker?.addEventListener('message', handleServiceWorkerMessage)

    if ('serviceWorker' in navigator) {
      void navigator.serviceWorker.getRegistration().then((registration) => {
        if (registration?.waiting) {
          setUpdateAvailable(true)
        }
      })

    }

    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
      window.removeEventListener('family-cookbook-sw-update', handleServiceWorkerUpdate)
      navigator.serviceWorker?.removeEventListener('message', handleServiceWorkerMessage)
    }
    // The service worker callback asks the current app instance to retry its durable pending snapshot.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (cookbook) {
      void persistCookbookSnapshot(OFFLINE_COOKBOOK_KEY, cookbook)
    }
  }, [cookbook])

  useEffect(() => {
    let isCancelled = false

    async function hydrateDurableSnapshot() {
      const pending = await loadCookbookSnapshot(PENDING_COOKBOOK_KEY)
      const cached = pending ?? (await loadCookbookSnapshot(OFFLINE_COOKBOOK_KEY))
      if (isCancelled || !cached) {
        return
      }

      setCookbook((current) => current ?? cached)
      setSelectedRecipeId((current) => current ?? parseRoute().recipeId ?? null)
      if (pending) {
        setHasPendingLocalChanges(true)
      }
    }

    void hydrateDurableSnapshot()

    return () => {
      isCancelled = true
    }
  }, [])

  useEffect(() => {
    if (!isOnline || !hasPendingLocalChanges || !cookbook || sessionState.status !== 'signed-in') {
      return
    }

    const timeout = window.setTimeout(() => {
      void saveCookbook(cookbook, 'Uploaded pending cookbook changes.', { skipConflictCheck: false })
    }, 4000)

    return () => window.clearTimeout(timeout)
    // saveCookbook intentionally reads the latest session and conflict state when the timer fires.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cookbook, hasPendingLocalChanges, isOnline, sessionState.status])

  useEffect(() => {
    if (!isOnline || sessionState.status !== 'signed-in') {
      return
    }

    void pushPendingSnapshotIfNeeded()
    const interval = window.setInterval(() => {
      void pushPendingSnapshotIfNeeded()
    }, 30000)

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        void pushPendingSnapshotIfNeeded()
        void refreshCookbook(true)
      }
    }

    document.addEventListener('visibilitychange', handleVisibilityChange)

    return () => {
      window.clearInterval(interval)
      document.removeEventListener('visibilitychange', handleVisibilityChange)
    }
    // Sync callbacks intentionally read current app state when fired.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOnline, sessionState.status])

  useEffect(() => {
    const handleHashChange = () => {
      const nextRoute = parseRoute()
      setActiveTab(nextRoute.tab)
      setSelectedRecipeId(nextRoute.recipeId ?? null)
      if (nextRoute.action === 'import') {
        setImportState({ isOpen: true, url: '', isLoading: false, message: null, importedRecipe: null })
      } else {
        setImportState((current) => (current.isOpen ? { isOpen: false, url: '', isLoading: false, message: null, importedRecipe: null } : current))
      }
      setSelectedLog((current) => {
        if (!nextRoute.logId || current?.log.id === nextRoute.logId) {
          return current
        }

        return null
      })
      if (!nextRoute.action || nextRoute.action === 'log-detail') {
        setEditingRecipeId(null)
        setRecipeDraft(null)
        setLoggingRecipeId(null)
        setLogDraft(null)
        setScaleState(null)
      }
    }

    window.addEventListener('hashchange', handleHashChange)
    return () => window.removeEventListener('hashchange', handleHashChange)
  }, [])

  const recipes = cookbook?.recipes ?? EMPTY_RECIPES

  /* eslint-disable react-hooks/set-state-in-effect */
  useEffect(() => {
    const route = parseRoute()
    const selectedRecipe = recipes.find((recipe) => recipe.id === route.recipeId)
    const log = selectedRecipe?.logs.find((item) => item.id === route.logId)

    if (selectedRecipe && log) {
      setSelectedLog({ recipeId: selectedRecipe.id, recipeTitle: selectedRecipe.title, log })
    }

    if (route.action === 'new' && !recipeDraft) {
      const defaultOwner =
        displayNameDraft || (sessionState.status === 'signed-in' ? sessionState.email : 'Family')
      setRecipeDraft(makeEmptyRecipeDraft(defaultOwner))
      setEditingRecipeId(null)
    }

    if (selectedRecipe && route.action === 'edit' && editingRecipeId !== selectedRecipe.id) {
      setRecipeDraft(recipeToDraft(selectedRecipe))
      setEditingRecipeId(selectedRecipe.id)
    }

    if (selectedRecipe && route.action === 'log' && loggingRecipeId !== selectedRecipe.id) {
      setLogDraft(makeEmptyLogDraft(selectedRecipe, displayNameDraft || (sessionState.status === 'signed-in' ? sessionState.email : 'Cook')))
      setLoggingRecipeId(selectedRecipe.id)
    }

    if (selectedRecipe && route.action === 'scale' && scaleState?.recipeId !== selectedRecipe.id) {
      setScaleState({ recipeId: selectedRecipe.id, factor: 1, source: 'multiplier' })
    }
    // Route hydration deliberately opens the requested sheet after recipes/session are available.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recipes])
  /* eslint-enable react-hooks/set-state-in-effect */

  const visibleRecipes = useMemo(() => {
    const query = recipeSearchText.trim().toLowerCase()

    return recipes
      .filter((recipe) => {
        const matchesSearch =
          !query ||
          recipe.title.toLowerCase().includes(query) ||
          recipe.summary.toLowerCase().includes(query) ||
          recipe.familyOwner.toLowerCase().includes(query) ||
          recipe.tags.some((tag) => tag.toLowerCase().includes(query))

        const matchesFilter =
          recipeFilter === 'all' ||
          (recipeFilter === 'favorites' && recipe.isFavorite) ||
          (recipeFilter === 'cooked' && recipe.logs.length > 0)

        return matchesSearch && matchesFilter
      })
      .sort((left, right) => compareRecipes(left, right, recipeSort))
  }, [recipeFilter, recipeSearchText, recipeSort, recipes])

  const selectedRecipe = useMemo(() => {
    return selectedRecipeId ? recipes.find((recipe) => recipe.id === selectedRecipeId) ?? null : null
  }, [recipes, selectedRecipeId])

  const activityItems = useMemo(() => {
    return recipes
      .flatMap((recipe) =>
        recipe.logs.map((log) => ({
          recipeId: recipe.id,
          recipeTitle: recipe.title,
          log,
        })),
      )
      .sort((left, right) => {
        return new Date(right.log.cookedOn).getTime() - new Date(left.log.cookedOn).getTime()
      })
  }, [recipes])

  const scaledIngredients = useMemo(() => {
    if (!selectedRecipe) {
      return []
    }

    const factor = scaleState?.recipeId === selectedRecipe.id ? scaleState.factor : 1

    return selectedRecipe.ingredients.map((ingredient) => ({
      ...ingredient,
      displayAmount: scaleIngredientAmount(ingredient.amount, factor),
    }))
  }, [scaleState, selectedRecipe])

  async function adoptSignedInSession(emailAddress: string, userId: string) {
    const profileName = await fetchProfileName(userId)
    setSessionState({
      status: 'signed-in',
      email: emailAddress,
      userId,
      displayName: profileName,
    })
    setDisplayNameDraft(profileName)
    await refreshCookbook(true, profileName || emailAddress)
  }

  async function fetchProfileName(userId: string) {
    if (!supabase) {
      return ''
    }

    const { data, error } = await supabase
      .from('profiles')
      .select('display_name')
      .eq('id', userId)
      .maybeSingle()

    if (error) {
      setAuthMessage(error.message)
      return ''
    }

    return data?.display_name ?? ''
  }

  async function refreshCookbook(isSilent = false, fallbackOwnerName = '') {
    if (!supabase) {
      return
    }

    const ownerName =
      fallbackOwnerName ||
      (sessionState.status === 'signed-in'
        ? displayNameDraft || sessionState.displayName || sessionState.email
        : '')

    if (!ownerName && sessionState.status !== 'signed-in') {
      return
    }

    if (!isSilent) {
      setDataNotice(null)
    }
    setIsRefreshing(true)

    const { data, error } = await supabase
      .from('shared_cookbooks')
      .select('payload, updated_at')
      .eq('slug', SHARED_COOKBOOK_SLUG)
      .maybeSingle()

    setIsRefreshing(false)

    if (error) {
      const cached = loadCachedCookbook()
      if (cached) {
        setCookbook(cached)
        setSelectedRecipeId((current) => current ?? parseRoute().recipeId ?? null)
        setDataNotice({
          kind: 'error',
          text: `${error.message} Showing the last offline snapshot.`,
        })
        return
      }

      setDataNotice({ kind: 'error', text: error.message })
      return
    }

    if (!data?.payload) {
      const defaultCookbook = makeEmptyCookbook(ownerName || 'Family')
      setCookbook(defaultCookbook)
      setSelectedRecipeId(null)
      if (!isSilent) {
        setDataNotice({
          kind: 'success',
          text: 'No shared cookbook exists yet. Create one from the web or push from native.',
        })
      }
      return
    }

    const snapshot = normaliseCookbookSnapshot(data.payload)
    if (hasPendingLocalChanges && cookbook && isRemoteNewer(snapshot, cookbook)) {
      setPendingConflict({
        message: 'You have local edits and the shared cookbook changed elsewhere. Choose which version to keep.',
        localSnapshot: cookbook,
        remoteSnapshot: snapshot,
        successMessage: 'Resolved sync conflict.',
      })
      return
    }

    setCookbook(snapshot)
    setSelectedRecipeId((current) => current ?? parseRoute().recipeId ?? null)
    setLastSyncedAt(new Date().toISOString())
    setLastSyncDirection('pull')
    setHasPendingLocalChanges(false)
    void removeCookbookSnapshot(PENDING_COOKBOOK_KEY)
    if (!isSilent) {
      setDataNotice({ kind: 'success', text: `Loaded ${snapshot.title}.` })
    }
  }

  async function saveCookbook(
    nextCookbook: CookbookSnapshot,
    successMessage: string,
    options: { skipConflictCheck?: boolean } = {},
  ) {
    if (!supabase || sessionState.status !== 'signed-in') {
      return
    }

    setCookbook(nextCookbook)
    setSelectedRecipeId((current) => current ?? parseRoute().recipeId ?? null)
    setHasPendingLocalChanges(true)
    void persistCookbookSnapshot(PENDING_COOKBOOK_KEY, nextCookbook)
    void registerPendingSnapshotSync()

    if (!isOnline) {
      setDataNotice({ kind: 'error', text: 'You are offline. Changes are saved locally and will push when online.' })
      return
    }

    setIsSavingCookbook(true)

    if (!options.skipConflictCheck && cookbook) {
      const remote = await fetchRemoteCookbook()
      if (remote.error) {
        setIsSavingCookbook(false)
        setDataNotice({
          kind: 'error',
          text: `${remote.error}. Changes are saved locally and will retry when sync is available.`,
        })
        return
      }

      if (remote.snapshot && isRemoteNewer(remote.snapshot, cookbook)) {
        setIsSavingCookbook(false)
        setPendingConflict({
          message: 'Another device has newer cookbook changes. Keep your web changes or use the shared version.',
          localSnapshot: nextCookbook,
          remoteSnapshot: remote.snapshot,
          successMessage,
        })
        return
      }
    }

    const payload = {
      slug: SHARED_COOKBOOK_SLUG,
      title: nextCookbook.title,
      payload: nextCookbook,
      updated_at: new Date().toISOString(),
    }

    const { error } = await supabase.from('shared_cookbooks').upsert(payload, { onConflict: 'slug' })
    setIsSavingCookbook(false)

    if (error) {
      setDataNotice({ kind: 'error', text: error.message })
      return
    }

    setLastSyncedAt(new Date().toISOString())
    setLastSyncDirection('push')
    setHasPendingLocalChanges(false)
    void removeCookbookSnapshot(PENDING_COOKBOOK_KEY)
    setDataNotice({ kind: 'success', text: successMessage })
  }

  async function updateCookbook(mutator: (draft: CookbookSnapshot) => void, successMessage: string) {
    if (!cookbook) {
      return
    }

    const nextCookbook = cloneCookbook(cookbook)
    mutator(nextCookbook)
    nextCookbook.updatedAt = new Date().toISOString()
    await saveCookbook(nextCookbook, successMessage)
  }

  async function handleAuthSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    if (!supabase) {
      return
    }

    setAuthMessage(null)
    const trimmedEmail = email.trim()

    if (authMode === 'sign-in') {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: trimmedEmail,
        password,
      })

      if (error) {
        setAuthMessage(error.message)
        return
      }

      if (!data.user) {
        setAuthMessage('Sign-in succeeded, but no user session was returned.')
        return
      }

      await adoptSignedInSession(data.user.email ?? trimmedEmail, data.user.id)
      setEmail('')
      setPassword('')
      return
    }

    if (!invitePasscode.trim()) {
      setAuthMessage('Invite passcode is required to create an account.')
      return
    }

    const { data: inviteData, error: inviteError } = await supabase.functions.invoke('invite-signup', {
      body: {
        email: trimmedEmail,
        password,
        invitePasscode: invitePasscode.trim(),
      },
    })

    if (inviteError) {
      setAuthMessage(inviteError.message)
      return
    }

    if (inviteData?.error) {
      setAuthMessage(String(inviteData.error))
      return
    }

    const { data, error } = await supabase.auth.signInWithPassword({
      email: trimmedEmail,
      password,
    })

    if (error) {
      setAuthMessage(error.message)
      return
    }

    if (!data.user) {
      setAuthMessage('Account was created, but sign-in did not return a user session.')
      return
    }

    await adoptSignedInSession(data.user.email ?? trimmedEmail, data.user.id)
    setEmail('')
    setPassword('')
    setInvitePasscode('')
  }

  async function handleSaveProfile() {
    if (!supabase || sessionState.status !== 'signed-in') {
      return
    }

    const trimmedName = displayNameDraft.trim()
    if (!trimmedName) {
      setAuthMessage('Display name cannot be empty.')
      return
    }

    setIsSavingProfile(true)
    const { error } = await supabase
      .from('profiles')
      .upsert({ id: sessionState.userId, display_name: trimmedName }, { onConflict: 'id' })
    setIsSavingProfile(false)

    if (error) {
      setAuthMessage(error.message)
      return
    }

    setSessionState({
      ...sessionState,
      displayName: trimmedName,
    })
    setAuthMessage('Profile updated.')
  }

  async function handleSignOut() {
    if (!supabase) {
      return
    }

    const { error } = await supabase.auth.signOut()
    if (error) {
      setAuthMessage(error.message)
    }

    setSessionState({ status: 'signed-out' })
    setCookbook(null)
    setSelectedRecipeId(null)
    setDisplayNameDraft('')
  }

  async function resolveConflictUsingRemote() {
    if (!pendingConflict) {
      return
    }

    const remoteSnapshot = pendingConflict.remoteSnapshot
    setCookbook(remoteSnapshot)
    setSelectedRecipeId(parseRoute().recipeId ?? null)
    setPendingConflict(null)
    setHasPendingLocalChanges(false)
    setLastSyncedAt(new Date().toISOString())
    setLastSyncDirection('pull')
    setDataNotice({ kind: 'success', text: 'Using the newer shared cookbook.' })
  }

  async function resolveConflictKeepingLocal() {
    if (!pendingConflict) {
      return
    }

    const localSnapshot = pendingConflict.localSnapshot
    const successMessage = pendingConflict.successMessage
    setPendingConflict(null)
    await saveCookbook(localSnapshot, successMessage, { skipConflictCheck: true })
  }

  async function installApp() {
    if (!installPrompt) {
      return
    }

    await installPrompt.prompt()
    await installPrompt.userChoice
    setInstallPrompt(null)
  }

  async function applyServiceWorkerUpdate() {
    if (!('serviceWorker' in navigator)) {
      return
    }

    const registration = await navigator.serviceWorker.getRegistration()
    localStorage.setItem(UPDATE_APPLIED_KEY, APP_VERSION)
    registration?.waiting?.postMessage({ type: 'SKIP_WAITING' })
    window.location.reload()
  }

  function navigateToTab(tab: TabKey) {
    setActiveTab(tab)
    closeTransientRoutes()
    window.location.hash = `/${tab}`
  }

  function navigateToRecipe(recipeId: string) {
    setActiveTab('recipes')
    setSelectedRecipeId(recipeId)
    closeTransientRoutes()
    window.location.hash = `/recipes/${recipeId}`
  }

  function closeTransientRoutes() {
    setEditingRecipeId(null)
    setRecipeDraft(null)
    setLoggingRecipeId(null)
    setLogDraft(null)
    setScaleState(null)
    setSelectedLog(null)
    setImportState({ isOpen: false, url: '', isLoading: false, message: null, importedRecipe: null })
  }

  function openCookLogDetail(recipeId: string, recipeTitle: string, log: CookLogSnapshot) {
    setSelectedLog({ recipeId, recipeTitle, log })
    window.location.hash = `/recipes/${recipeId}/logs/${log.id}`
  }

  function closeCookLogDetail() {
    const recipeId = selectedLog?.recipeId
    setSelectedLog(null)
    window.location.hash = recipeId ? `/recipes/${recipeId}` : `/${activeTab}`
  }

  async function pushPendingSnapshotIfNeeded() {
    const pendingSnapshot = await loadCookbookSnapshot(PENDING_COOKBOOK_KEY)
    if (!pendingSnapshot || !isOnline || sessionState.status !== 'signed-in') {
      return
    }

    await saveCookbook(pendingSnapshot, 'Uploaded pending cookbook changes.', { skipConflictCheck: false })
  }

  async function registerPendingSnapshotSync() {
    if (!('serviceWorker' in navigator)) {
      return
    }

    try {
      const registration = (await navigator.serviceWorker.ready) as ServiceWorkerSyncRegistration
      await registration.sync?.register('family-cookbook-pending-sync')
      registration.active?.postMessage({ type: 'PENDING_COOKBOOK_CHANGED' })
    } catch {
      // Background Sync is optional; foreground timers and online/visibility retries still handle pending snapshots.
    }
  }

  async function handlePullRefresh() {
    setIsPulling(true)
    await refreshCookbook(true)
    setPullDistance(0)
    setIsPulling(false)
  }

  function handlePullStart(event: PointerEvent<HTMLElement>) {
    if (event.pointerType === 'mouse' || window.scrollY > 4) {
      return
    }

    event.currentTarget.dataset.pullStart = String(event.clientY)
  }

  function handlePullMove(event: PointerEvent<HTMLElement>) {
    const start = Number(event.currentTarget.dataset.pullStart)
    if (!start || window.scrollY > 4) {
      return
    }

    const distance = Math.max(0, Math.min(96, event.clientY - start))
    setPullDistance(distance)
  }

  function handlePullEnd(event: PointerEvent<HTMLElement>) {
    delete event.currentTarget.dataset.pullStart
    if (pullDistance > 72) {
      void handlePullRefresh()
      return
    }

    setPullDistance(0)
  }

  function swipeHandlers(actions: SwipeAction) {
    return {
      onPointerDown: (event: PointerEvent<HTMLElement>) => {
        event.currentTarget.dataset.swipeStart = String(event.clientX)
      },
      onPointerMove: (event: PointerEvent<HTMLElement>) => {
        const start = Number(event.currentTarget.dataset.swipeStart)
        if (!start) {
          return
        }

        const delta = Math.max(-96, Math.min(96, event.clientX - start))
        if (Math.abs(delta) < 12) {
          return
        }

        setSwipeFeedback({
          id: actions.id,
          offset: delta,
          label: delta > 0 ? actions.rightLabel ?? 'Swipe action' : actions.leftLabel ?? 'Swipe action',
        })
      },
      onPointerUp: (event: PointerEvent<HTMLElement>) => {
        const start = Number(event.currentTarget.dataset.swipeStart)
        delete event.currentTarget.dataset.swipeStart
        setSwipeFeedback(null)
        if (!start) {
          return
        }

        const delta = event.clientX - start
        if (delta > 72) {
          actions.onRight?.()
        } else if (delta < -72) {
          actions.onLeft?.()
        }
      },
      onPointerCancel: (event: PointerEvent<HTMLElement>) => {
        delete event.currentTarget.dataset.swipeStart
        setSwipeFeedback(null)
      },
    }
  }

  function openNewRecipeEditor() {
    setEditingRecipeId(null)
    const defaultOwner =
      displayNameDraft || (sessionState.status === 'signed-in' ? sessionState.email : 'Family')
    setRecipeDraft(makeEmptyRecipeDraft(defaultOwner))
    window.location.hash = '/recipes/new'
  }

  function openRecipeEditor(recipe: RecipeSnapshot) {
    setEditingRecipeId(recipe.id)
    setRecipeDraft(recipeToDraft(recipe))
    window.location.hash = `/recipes/${recipe.id}/edit`
  }

  function closeRecipeEditor() {
    const recipeId = editingRecipeId
    setEditingRecipeId(null)
    setRecipeDraft(null)
    window.location.hash = recipeId ? `/recipes/${recipeId}` : '/recipes'
  }

  async function saveRecipeDraft() {
    if (!recipeDraft) {
      return
    }

    if (!recipeDraft.title.trim()) {
      setDataNotice({ kind: 'error', text: 'Recipe title cannot be empty.' })
      return
    }

    const existingRecipe = editingRecipeId ? recipes.find((item) => item.id === editingRecipeId) ?? null : null
    const recipe = draftToRecipe(recipeDraft, existingRecipe)

    if (editingRecipeId) {
      await updateCookbook((draft) => {
        draft.recipes = draft.recipes.map((item) => (item.id === editingRecipeId ? recipe : item))
      }, 'Recipe updated.')
    } else {
      await updateCookbook((draft) => {
        draft.recipes = [recipe, ...draft.recipes]
      }, 'Recipe created.')
      setSelectedRecipeId(recipe.id)
    }

    closeRecipeEditor()
  }

  async function deleteRecipe(recipeId: string) {
    await updateCookbook((draft) => {
      draft.recipes = draft.recipes.filter((recipe) => recipe.id !== recipeId)
    }, 'Recipe deleted.')

    setSelectedRecipeId((current) => (current === recipeId ? null : current))
    if (selectedRecipeId === recipeId) {
      window.location.hash = '/recipes'
    }
  }

  async function toggleFavorite(recipeId: string) {
    await updateCookbook((draft) => {
      draft.recipes = draft.recipes.map((recipe) =>
        recipe.id === recipeId
          ? {
              ...recipe,
              isFavorite: !recipe.isFavorite,
              updatedAt: new Date().toISOString(),
            }
          : recipe,
      )
    }, 'Favorite updated.')
  }

  async function addRecipeIngredientsToShopping(recipe: RecipeSnapshot) {
    await updateCookbook((draft) => {
      const nextSortOrder = getNextShoppingSortOrder(draft.shoppingItems)
      const additions = recipe.ingredients.map((ingredient, index) => ({
        id: createId(),
        itemName: ingredient.name,
        amountText: ingredient.amount,
        sourceRecipeTitle: recipe.title,
        note: '',
        isChecked: false,
        sortOrder: nextSortOrder + index,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      }))
      draft.shoppingItems = [...draft.shoppingItems, ...additions]
    }, 'Ingredients added to shopping list.')
  }

  function openLogEditor(recipe: RecipeSnapshot) {
    setLoggingRecipeId(recipe.id)
    setLogDraft(makeEmptyLogDraft(recipe, displayNameDraft || (sessionState.status === 'signed-in' ? sessionState.email : 'Cook')))
    window.location.hash = `/recipes/${recipe.id}/log`
  }

  function closeLogEditor() {
    const recipeId = loggingRecipeId
    setLoggingRecipeId(null)
    setLogDraft(null)
    window.location.hash = recipeId ? `/recipes/${recipeId}` : '/recipes'
  }

  async function saveLogDraft() {
    if (!logDraft || !loggingRecipeId) {
      return
    }

    if (!logDraft.tweakSummary.trim() && !logDraft.notes.trim()) {
      setDataNotice({ kind: 'error', text: 'Add a tweak summary or notes before saving a cook log.' })
      return
    }

    const newLog = draftToCookLog(logDraft)
    await updateCookbook((draft) => {
      draft.recipes = draft.recipes.map((recipe) =>
        recipe.id === loggingRecipeId
          ? {
              ...recipe,
              updatedAt: new Date().toISOString(),
              logs: [newLog, ...recipe.logs],
            }
          : recipe,
      )
    }, 'Cook log saved.')
    closeLogEditor()
  }

  async function deleteLog(recipeId: string, logId: string) {
    await updateCookbook((draft) => {
      draft.recipes = draft.recipes.map((recipe) =>
        recipe.id === recipeId
          ? {
              ...recipe,
              updatedAt: new Date().toISOString(),
              logs: recipe.logs.filter((log) => log.id !== logId),
            }
          : recipe,
      )
    }, 'Cook log deleted.')
  }

  async function saveManualShoppingItem() {
    const itemName = shoppingDraft.itemName.trim()
    if (!itemName) {
      return
    }

    await updateCookbook((draft) => {
      draft.shoppingItems = [
        {
          id: createId(),
          itemName,
          amountText: shoppingDraft.amountText.trim(),
          sourceRecipeTitle: '',
          note: shoppingDraft.note.trim(),
          isChecked: false,
          sortOrder: getNextShoppingSortOrder(draft.shoppingItems),
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
        ...draft.shoppingItems,
      ]
    }, 'Shopping item added.')

    setShoppingDraft({ itemName: '', amountText: '', note: '' })
  }

  async function toggleShoppingItem(itemId: string) {
    await updateCookbook((draft) => {
      draft.shoppingItems = draft.shoppingItems.map((item) =>
        item.id === itemId
          ? {
              ...item,
              isChecked: !item.isChecked,
              updatedAt: new Date().toISOString(),
            }
          : item,
      )
    }, 'Shopping list updated.')
  }

  async function deleteShoppingItem(itemId: string) {
    await updateCookbook((draft) => {
      draft.shoppingItems = draft.shoppingItems.filter((item) => item.id !== itemId)
    }, 'Shopping item removed.')
  }

  async function updateShoppingItemNote(itemId: string, note: string) {
    await updateCookbook((draft) => {
      draft.shoppingItems = draft.shoppingItems.map((item) =>
        item.id === itemId
          ? {
              ...item,
              note: note.trim(),
              updatedAt: new Date().toISOString(),
            }
          : item,
      )
    }, 'Shopping note updated.')
  }

  async function clearCheckedItems() {
    await updateCookbook((draft) => {
      draft.shoppingItems = draft.shoppingItems.filter((item) => !item.isChecked)
    }, 'Checked items cleared.')
  }

  async function fetchRecipeImportPreview() {
    const normalizedUrl = normalizeRecipeUrl(importState.url)
    if (!normalizedUrl) {
      setImportState((current) => ({ ...current, message: 'Enter a recipe URL first.' }))
      return
    }

    setImportState((current) => ({ ...current, isLoading: true, message: null, importedRecipe: null }))

    try {
      const response = await fetch(normalizedUrl)
      const html = await response.text()
      const imported = parseRecipeFromHtml(normalizedUrl, html)

      setImportState((current) => ({
        ...current,
        url: normalizedUrl,
        isLoading: false,
        message: null,
        importedRecipe: imported,
      }))
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : 'The recipe page could not be loaded. Some sites block browser imports because of CORS.'

      setImportState((current) => ({
        ...current,
        isLoading: false,
        message,
        importedRecipe: null,
      }))
    }
  }

  function saveImportedRecipePreview() {
    if (!importState.importedRecipe) {
      return
    }

    setEditingRecipeId(null)
    setRecipeDraft(recipeToDraft(importState.importedRecipe))
    setImportState({
      isOpen: false,
      url: '',
      isLoading: false,
      message: null,
      importedRecipe: null,
    })
    window.location.hash = '/recipes'
    setDataNotice({ kind: 'success', text: 'Recipe imported. Review and save it.' })
  }

  function openScaleForRecipe(recipe: RecipeSnapshot) {
    setScaleState({
      recipeId: recipe.id,
      factor: 1,
      source: 'multiplier',
    })
    window.location.hash = `/recipes/${recipe.id}/scale`
  }

  function applyScaleMultiplier(multiplier: number) {
    if (!selectedRecipe) {
      return
    }

    setScaleState({
      recipeId: selectedRecipe.id,
      factor: multiplier,
      source: 'multiplier',
    })
  }

  function applyScaleByIngredient(ingredientId: string, newAmountText: string) {
    if (!selectedRecipe) {
      return
    }

    const ingredient = selectedRecipe.ingredients.find((item) => item.id === ingredientId)
    if (!ingredient) {
      return
    }

    const originalAmount = parseLeadingAmount(ingredient.amount)
    const targetAmount = parseLeadingAmount(newAmountText)
    if (!originalAmount || !targetAmount) {
      setDataNotice({
        kind: 'error',
        text: 'That ingredient amount could not be scaled. Use a numeric or fractional amount.',
      })
      return
    }

    setScaleState({
      recipeId: selectedRecipe.id,
      factor: targetAmount / originalAmount,
      source: 'ingredient',
    })
  }

  async function handlePhotoSelection(event: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files ?? [])
    if (!files.length || !logDraft) {
      return
    }

    const photos = await Promise.all(
      files.map(async (file) => ({
        id: createId(),
        stage: 'Cook',
        caption: file.name,
        imageData: await readFileAsDataUrl(file),
      })),
    )

    setLogDraft({
      ...logDraft,
      photos: [...logDraft.photos, ...photos],
    })
    event.target.value = ''
  }

  return (
    <div className="app-shell">
      {updateAvailable ? (
        <aside className="update-banner">
          <div>
            <strong>New cookbook app version ready</strong>
            <span>{APP_VERSION}: background sync wakeups, smoother gestures, deeper links, and update confirmations.</span>
          </div>
          <ul>
            <li>Service-worker sync retry signals for pending snapshots</li>
            <li>Routeable recipe sheets and cook-log modals</li>
            <li>Polished swipe and refresh feedback</li>
          </ul>
          <button className="primary-button small" onClick={() => void applyServiceWorkerUpdate()}>
            Update Now
          </button>
        </aside>
      ) : null}
      <header className="app-header">
        <div>
          <p className="eyebrow">Family Cookbook</p>
        </div>
        <div className="header-status">
          {sessionState.status === 'signed-in' ? (
            <>
              <button className="icon-status-button" onClick={() => navigateToTab('profile')} aria-label="Profile">
                <span aria-hidden="true">◎</span>
              </button>
              <button
                className="sync-icon-button"
                onClick={() => void refreshCookbook()}
                aria-label="Sync status"
                title={lastSyncDirection ? `${lastSyncDirection === 'pull' ? 'Pulled' : 'Pushed'} ${lastSyncedAt ? formatRelativeDate(lastSyncedAt) : ''}` : 'Sync status'}
              >
                <span aria-hidden="true">{isSavingCookbook || isRefreshing ? '↻' : hasPendingLocalChanges ? '↑' : '✓'}</span>
                <span>
                  {syncWakeupSource
                    ? 'Retried'
                    : lastSyncedAt
                    ? formatRelativeDate(lastSyncedAt)
                    : cookbook
                      ? formatRelativeDate(cookbook.updatedAt)
                      : 'No sync'}
                </span>
              </button>
              {installPrompt || updateAvailable || !isOnline ? (
                <button className="icon-status-button" onClick={() => void (updateAvailable ? applyServiceWorkerUpdate() : installApp())} aria-label="PWA status">
                  <span aria-hidden="true">{isOnline ? '⌂' : '!'}</span>
                </button>
              ) : null}
            </>
          ) : (
            <button className="icon-status-button" onClick={() => setAuthMode('sign-in')} aria-label="Sign in">
              <span aria-hidden="true">◎</span>
            </button>
          )}
        </div>
      </header>

      {sessionState.status !== 'signed-in' ? (
        <main className="landing-layout">
          <section className="auth-panel">
            <div className="auth-mode-toggle" role="tablist" aria-label="Authentication mode">
              <button className={authMode === 'sign-in' ? 'is-active' : ''} onClick={() => setAuthMode('sign-in')} type="button">
                Sign In
              </button>
              <button className={authMode === 'sign-up' ? 'is-active' : ''} onClick={() => setAuthMode('sign-up')} type="button">
                Create Account
              </button>
            </div>

            <form className="auth-form" onSubmit={handleAuthSubmit}>
              <label>
                Email
                <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required />
              </label>

              <label>
                Password
                <input
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  autoComplete={authMode === 'sign-in' ? 'current-password' : 'new-password'}
                  required
                />
              </label>

              {authMode === 'sign-up' ? (
                <label>
                  Invite Passcode
                  <input
                    type="password"
                    value={invitePasscode}
                    onChange={(event) => setInvitePasscode(event.target.value)}
                    autoComplete="one-time-code"
                    required
                  />
                </label>
              ) : null}

              <button
                className="primary-button"
                type="submit"
                disabled={authMode === 'sign-up' && !invitePasscode.trim()}
              >
                {authMode === 'sign-in' ? 'Sign In' : 'Create Account'}
              </button>
            </form>

            {authMessage ? <p className="message error">{authMessage}</p> : null}
            {sessionState.status === 'missing-config' ? (
              <p className="message error">
                Add <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code> to
                <code> .env.local</code> before using the web app.
              </p>
            ) : null}
          </section>
        </main>
      ) : (
        <main
          className="dashboard-layout"
          onPointerDown={handlePullStart}
          onPointerMove={handlePullMove}
          onPointerUp={handlePullEnd}
          onPointerCancel={handlePullEnd}
        >
          <nav className="sidebar-nav" aria-label="Sections">
            <button className={activeTab === 'recipes' ? 'is-active' : ''} onClick={() => navigateToTab('recipes')}>
              Recipes
            </button>
            <button className={activeTab === 'activity' ? 'is-active' : ''} onClick={() => navigateToTab('activity')}>
              Activity
            </button>
            <button className={activeTab === 'shopping' ? 'is-active' : ''} onClick={() => navigateToTab('shopping')}>
              Shopping
            </button>
            <button className={activeTab === 'profile' ? 'is-active' : ''} onClick={() => navigateToTab('profile')}>
              Profile
            </button>
          </nav>

          <section className="content-panel">
            {pullDistance > 0 || isPulling ? (
              <div className="pull-indicator" style={{ transform: `translateY(${Math.round(pullDistance / 3)}px)` }}>
                {isPulling ? 'Refreshing...' : pullDistance > 72 ? 'Release to refresh' : 'Pull to refresh'}
              </div>
            ) : null}
            {dataNotice ? <p className={`message ${dataNotice.kind}`}>{dataNotice.text}</p> : null}

            {activeTab === 'recipes' ? (
              <section className="single-column">
                {selectedRecipe ? (
                  <article className="recipe-detail recipe-page">
                    <div className="section-heading recipe-page-heading">
                      <button className="icon-button" onClick={() => {
                        setSelectedRecipeId(null)
                        window.location.hash = '/recipes'
                      }} aria-label="Back to recipes">
                        <span aria-hidden="true">‹</span>
                      </button>
                      <div>
                        <h2>{selectedRecipe.title}</h2>
                        <p className="section-subtitle">{selectedRecipe.summary}</p>
                      </div>
                      <div className="icon-action-row">
                        <button className="icon-button" onClick={() => void toggleFavorite(selectedRecipe.id)} aria-label={selectedRecipe.isFavorite ? 'Unfavorite' : 'Favorite'}>
                          <span aria-hidden="true">{selectedRecipe.isFavorite ? '★' : '☆'}</span>
                        </button>
                        <button className="icon-button" onClick={() => openScaleForRecipe(selectedRecipe)} aria-label="Scale recipe">
                          <span aria-hidden="true">↕</span>
                        </button>
                        <button className="icon-button" onClick={() => void addRecipeIngredientsToShopping(selectedRecipe)} aria-label="Add to shopping">
                          <span aria-hidden="true">+</span>
                        </button>
                        <button className="icon-button" onClick={() => openLogEditor(selectedRecipe)} aria-label="Log cook">
                          <span aria-hidden="true">◷</span>
                        </button>
                        <button className="icon-button" onClick={() => openRecipeEditor(selectedRecipe)} aria-label="Edit recipe">
                          <span aria-hidden="true">✎</span>
                        </button>
                        <button className="icon-button danger-icon" onClick={() => void deleteRecipe(selectedRecipe.id)} aria-label="Delete recipe">
                          <span aria-hidden="true">×</span>
                        </button>
                      </div>
                    </div>

                    <div className="meta-pill-row">
                      {selectedRecipe.tags.map((tag) => (
                        <span key={tag} className="meta-pill">
                          {tag}
                        </span>
                      ))}
                    </div>

                    <section className="detail-section">
                      <div className="section-heading compact">
                        <h3>Ingredients</h3>
                        {scaleState?.recipeId === selectedRecipe.id ? (
                          <button className="ghost-button small" onClick={() => setScaleState(null)}>
                            Reset Scale
                          </button>
                        ) : null}
                      </div>
                      <ul className="stack-list">
                        {scaledIngredients.map((ingredient) => (
                          <li key={ingredient.id}>
                            <strong>{ingredient.displayAmount}</strong> {ingredient.name}
                          </li>
                        ))}
                      </ul>
                    </section>

                    <section className="detail-section">
                      <h3>Steps</h3>
                      <ol className="stack-list ordered">
                        {selectedRecipe.steps.map((step) => (
                          <li key={step.id}>
                            <strong>{step.title}</strong>
                            <p>{step.instruction}</p>
                          </li>
                        ))}
                      </ol>
                    </section>

                    <section className="detail-section">
                      <h3>Cook History</h3>
                      {selectedRecipe.logs.length === 0 ? (
                        <p className="section-subtitle">No cook logs yet.</p>
                      ) : (
                        <div className="detail-stack">
                          {selectedRecipe.logs.map((log) => (
                            <article key={log.id} className="activity-card">
                              <div className="activity-card-header">
                                <div>
                                  <h3>{formatDate(log.cookedOn)}</h3>
                                  <span>{log.cookName} • {renderStars(log.rating)} • {log.mood}</span>
                                </div>
                                <div className="button-row wrap">
                                  <button
                                    className="ghost-button small"
                                    onClick={() => openCookLogDetail(selectedRecipe.id, selectedRecipe.title, log)}
                                  >
                                    View Log
                                  </button>
                                  <button className="danger-button small" onClick={() => void deleteLog(selectedRecipe.id, log.id)}>
                                    Delete Log
                                  </button>
                                </div>
                              </div>
                              {log.tweakSummary ? <p><strong>Tweaks:</strong> {log.tweakSummary}</p> : null}
                              {log.notes ? <p><strong>Notes:</strong> {log.notes}</p> : null}
                              {log.nextTimeNote ? <p><strong>Next Time:</strong> {log.nextTimeNote}</p> : null}
                              {log.observations.length > 0 ? (
                                <ul className="stack-list inset">
                                  {log.observations.map((observation) => (
                                    <li key={observation.id}>
                                      <strong>{observation.stepTitle}</strong> {observation.note}
                                    </li>
                                  ))}
                                </ul>
                              ) : null}
                              {log.photos.length > 0 ? (
                                <div className="photo-grid">
                                  {log.photos.map((photo) => (
                                    <figure key={photo.id} className="photo-card">
                                      {photo.imageData ? <img src={decodePhotoSource(photo)} alt={photo.caption || photo.stage} /> : null}
                                      <figcaption>{photo.caption || photo.stage}</figcaption>
                                    </figure>
                                  ))}
                                </div>
                              ) : null}
                            </article>
                          ))}
                        </div>
                      )}
                    </section>
                  </article>
                ) : (
                  <>
                    <div className="section-heading recipe-list-heading">
                      <div>
                        <h2>{cookbook?.title ?? 'Family Cookbook'}</h2>
                        <p className="section-subtitle">Create, import, scale, and log recipes from the same shared snapshot.</p>
                      </div>
                      <div className="icon-action-row">
                        <button className="icon-button" onClick={() => void refreshCookbook()} aria-label="Pull shared data">
                          <span aria-hidden="true">{isRefreshing ? '↻' : '↓'}</span>
                        </button>
                        <button
                          className="icon-button"
                          onClick={() => {
                            setImportState({ isOpen: true, url: '', isLoading: false, message: null, importedRecipe: null })
                            window.location.hash = '/recipes/import'
                          }}
                          aria-label="Import from URL"
                        >
                          <span aria-hidden="true">↧</span>
                        </button>
                        <button className="icon-button primary-icon" onClick={openNewRecipeEditor} aria-label="New recipe">
                          <span aria-hidden="true">+</span>
                        </button>
                      </div>
                    </div>

                    <section className="recipe-controls compact-controls">
                      <label className="search-field" aria-label="Search recipes">
                        <span aria-hidden="true">⌕</span>
                        <input
                          type="search"
                          placeholder="Search recipes, owners, or tags"
                          value={recipeSearchText}
                          onChange={(event) => setRecipeSearchText(event.target.value)}
                        />
                      </label>
                      <div className="control-menu-wrap">
                        <button className="icon-button" onClick={() => setRecipeOptionsMenu((current) => current === 'filter' ? null : 'filter')} aria-label="Filter recipes">
                          <span aria-hidden="true">◇</span>
                        </button>
                        {recipeOptionsMenu === 'filter' ? (
                          <div className="option-popover">
                            {(['all', 'favorites', 'cooked'] as RecipeFilter[]).map((filter) => (
                              <button
                                key={filter}
                                className={recipeFilter === filter ? 'is-active' : ''}
                                onClick={() => {
                                  setRecipeFilter(filter)
                                  setRecipeOptionsMenu(null)
                                }}
                              >
                                {filter === 'all' ? 'All' : filter === 'favorites' ? 'Favorites' : 'Cooked'}
                              </button>
                            ))}
                          </div>
                        ) : null}
                      </div>
                      <div className="control-menu-wrap">
                        <button className="icon-button" onClick={() => setRecipeOptionsMenu((current) => current === 'sort' ? null : 'sort')} aria-label="Sort recipes">
                          <span aria-hidden="true">≡</span>
                        </button>
                        {recipeOptionsMenu === 'sort' ? (
                          <div className="option-popover align-right">
                            {(['title', 'owner', 'recent'] as RecipeSort[]).map((sort) => (
                              <button
                                key={sort}
                                className={recipeSort === sort ? 'is-active' : ''}
                                onClick={() => {
                                  setRecipeSort(sort)
                                  setRecipeOptionsMenu(null)
                                }}
                              >
                                {sort === 'title' ? 'Title' : sort === 'owner' ? 'Owner' : 'Recent Activity'}
                              </button>
                            ))}
                          </div>
                        ) : null}
                      </div>
                      <div className="view-toggle" aria-label="Recipe view mode">
                        <button className={recipeViewMode === 'cards' ? 'is-active' : ''} onClick={() => setRecipeViewMode('cards')} aria-label="Card view">
                          ▦
                        </button>
                        <button className={recipeViewMode === 'list' ? 'is-active' : ''} onClick={() => setRecipeViewMode('list')} aria-label="List view">
                          ☰
                        </button>
                      </div>
                    </section>

                    <div className={`recipe-list ${recipeViewMode === 'list' ? 'is-list-view' : ''}`}>
                    {recipes.length === 0 ? (
                      <EmptyState title="No recipes yet." subtitle="Create one here or import a recipe page." compact />
                    ) : visibleRecipes.length === 0 ? (
                      <EmptyState title="No matching recipes." subtitle="Adjust the search, filter, or sort controls." compact />
                    ) : (
                      visibleRecipes.map((recipe) => (
                        <article
                          key={recipe.id}
                          className="recipe-card"
                          style={swipeFeedback?.id === `recipe-${recipe.id}` ? { transform: `translateX(${swipeFeedback.offset}px)` } : undefined}
                          {...swipeHandlers({
                            id: `recipe-${recipe.id}`,
                            rightLabel: recipe.isFavorite ? 'Unfavorite' : 'Favorite',
                            leftLabel: 'Delete',
                            onRight: () => void toggleFavorite(recipe.id),
                            onLeft: () => void deleteRecipe(recipe.id),
                          })}
                        >
                          {swipeFeedback?.id === `recipe-${recipe.id}` ? <span className="swipe-hint">{swipeFeedback.label}</span> : null}
                          <button type="button" className="recipe-card-main" onClick={() => navigateToRecipe(recipe.id)}>
                            <div className="recipe-card-header">
                              <strong>{recipe.title}</strong>
                              {recipe.isFavorite ? <span aria-label="favorite">★</span> : null}
                            </div>
                            <p>{recipe.summary}</p>
                            <span>{recipe.familyOwner}</span>
                            {recipe.tags.length ? (
                              <span>{recipe.tags.join(' • ')}</span>
                            ) : null}
                            {recipe.logs[0] ? (
                              <span>{latestCookSummary(recipe)}</span>
                            ) : null}
                          </button>
                          <div className="recipe-card-actions">
                            <button className="ghost-button small" onClick={() => void toggleFavorite(recipe.id)}>
                              {recipe.isFavorite ? '★' : '☆'}
                            </button>
                            <button className="danger-button small" onClick={() => void deleteRecipe(recipe.id)}>
                              ×
                            </button>
                          </div>
                        </article>
                      ))
                    )}
                    </div>
                  </>
                )}
              </section>
            ) : null}

            {activeTab === 'activity' ? (
              <section className="single-column">
                <div className="section-heading">
                  <div>
                    <h2>Recent Activity</h2>
                    <p className="section-subtitle">Every cook log across the shared cookbook in one place.</p>
                  </div>
                </div>
                {activityItems.length === 0 ? (
                  <EmptyState title="No activity yet." subtitle="Cook logs created on web or native will appear here." />
                ) : (
                  <div className="detail-stack">
                    {activityItems.map(({ recipeId, recipeTitle, log }) => (
                      <article
                        className="activity-card"
                        key={log.id}
                        style={swipeFeedback?.id === `log-${log.id}` ? { transform: `translateX(${swipeFeedback.offset}px)` } : undefined}
                        {...swipeHandlers({
                          id: `log-${log.id}`,
                          rightLabel: 'View Log',
                          leftLabel: 'Delete',
                          onRight: () => openCookLogDetail(recipeId, recipeTitle, log),
                          onLeft: () => void deleteLog(recipeId, log.id),
                        })}
                      >
                        {swipeFeedback?.id === `log-${log.id}` ? <span className="swipe-hint">{swipeFeedback.label}</span> : null}
                        <div className="activity-card-header">
                          <div>
                            <h3>{recipeTitle}</h3>
                            <span>{formatDate(log.cookedOn)} • {log.cookName} • {renderStars(log.rating)}</span>
                          </div>
                          <div className="button-row wrap">
                            <button className="ghost-button small" onClick={() => {
                              navigateToRecipe(recipeId)
                            }}>
                              View Recipe
                            </button>
                            <button className="ghost-button small" onClick={() => openCookLogDetail(recipeId, recipeTitle, log)}>
                              View Log
                            </button>
                            <button className="danger-button small" onClick={() => void deleteLog(recipeId, log.id)}>
                              Delete Log
                            </button>
                          </div>
                        </div>
                        {log.tweakSummary ? <p><strong>Tweaks:</strong> {log.tweakSummary}</p> : null}
                        {log.notes ? <p><strong>Notes:</strong> {log.notes}</p> : null}
                        {log.nextTimeNote ? <p><strong>Next Time:</strong> {log.nextTimeNote}</p> : null}
                      </article>
                    ))}
                  </div>
                )}
              </section>
            ) : null}

            {activeTab === 'shopping' ? (
              <section className="single-column">
                <div className="section-heading">
                  <div>
                    <h2>Shopping List</h2>
                    <p className="section-subtitle">Shared grocery planning with the same snapshot sync as the native app.</p>
                  </div>
                  <button className="ghost-button" onClick={() => void clearCheckedItems()}>
                    Clear Checked
                  </button>
                </div>

                <section className="detail-section shopping-add-section">
                  <div className="inline-form shopping-add-form">
                    <input
                      type="text"
                      placeholder="Item"
                      value={shoppingDraft.itemName}
                      onChange={(event) => setShoppingDraft({ ...shoppingDraft, itemName: event.target.value })}
                    />
                    <input
                      type="text"
                      placeholder="Amount"
                      value={shoppingDraft.amountText}
                      onChange={(event) => setShoppingDraft({ ...shoppingDraft, amountText: event.target.value })}
                    />
                    <input
                      type="text"
                      placeholder="Note"
                      value={shoppingDraft.note}
                      onChange={(event) => setShoppingDraft({ ...shoppingDraft, note: event.target.value })}
                    />
                    <button className="primary-button" onClick={() => void saveManualShoppingItem()}>
                      Add Item
                    </button>
                  </div>
                </section>

                {cookbook?.shoppingItems.length ? (
                  <div className="shopping-list-section" aria-label="Shopping list items">
                    {sortShoppingItems(cookbook.shoppingItems).map((item) => (
                      <article
                        className={`shopping-row ${item.isChecked ? 'is-checked' : ''}`}
                        key={item.id}
                        style={swipeFeedback?.id === `shopping-${item.id}` ? { transform: `translateX(${swipeFeedback.offset}px)` } : undefined}
                        {...swipeHandlers({
                          id: `shopping-${item.id}`,
                          rightLabel: item.isChecked ? 'Uncheck' : 'Check',
                          leftLabel: 'Delete',
                          onRight: () => void toggleShoppingItem(item.id),
                          onLeft: () => void deleteShoppingItem(item.id),
                        })}
                      >
                        {swipeFeedback?.id === `shopping-${item.id}` ? <span className="swipe-hint">{swipeFeedback.label}</span> : null}
                        <button className="check-button" onClick={() => void toggleShoppingItem(item.id)}>
                          {item.isChecked ? '✓' : ''}
                        </button>
                        <div className="shopping-row-content">
                          <strong>{item.itemName}</strong>
                          <span>{item.amountText || 'No amount'}</span>
                          {item.sourceRecipeTitle ? <span>From {item.sourceRecipeTitle}</span> : null}
                          <input
                            className="inline-note-input"
                            type="text"
                            placeholder="Note"
                            defaultValue={item.note}
                            onBlur={(event) => {
                              if (event.target.value !== item.note) {
                                void updateShoppingItemNote(item.id, event.target.value)
                              }
                            }}
                          />
                        </div>
                        <button className="danger-button small shopping-delete-button" onClick={() => void deleteShoppingItem(item.id)} aria-label={`Delete ${item.itemName}`}>
                          ×
                        </button>
                      </article>
                    ))}
                  </div>
                ) : (
                  <EmptyState title="Shopping list is empty." subtitle="Add an item here or send ingredients from a recipe." />
                )}
              </section>
            ) : null}

            {activeTab === 'profile' ? (
              <section className="single-column">
                <div className="section-heading">
                  <div>
                    <h2>Profile</h2>
                    <p className="section-subtitle">Account identity, sync, and shared cookbook metadata.</p>
                  </div>
                  <div className="button-row wrap">
                    <button className="ghost-button" onClick={() => void refreshCookbook()}>
                      {isRefreshing ? 'Refreshing…' : 'Pull Shared Cookbook'}
                    </button>
                    <button
                      className="ghost-button"
                      onClick={() => {
                        if (cookbook) {
                          void saveCookbook(cookbook, 'Current cookbook snapshot pushed.')
                        }
                      }}
                    >
                      Push Current Snapshot
                    </button>
                  </div>
                </div>

                <section className="detail-section">
                  <label className="form-field">
                    <span>Display Name</span>
                    <input type="text" value={displayNameDraft} onChange={(event) => setDisplayNameDraft(event.target.value)} />
                  </label>
                  <div className="profile-meta">
                    <span>Email</span>
                    <strong>{sessionState.status === 'signed-in' ? sessionState.email : ''}</strong>
                  </div>
                  <div className="profile-meta">
                    <span>Shared Cookbook Title</span>
                    <strong>{cookbook?.title ?? 'Family Cookbook'}</strong>
                  </div>
                  <div className="button-row wrap">
                    <button className="primary-button" onClick={() => void handleSaveProfile()} disabled={isSavingProfile}>
                      {isSavingProfile ? 'Saving…' : 'Save Profile'}
                    </button>
                    <button className="danger-button" onClick={() => void handleSignOut()}>
                      Sign Out
                    </button>
                  </div>
                </section>
              </section>
            ) : null}
          </section>
        </main>
      )}

      {recipeDraft ? (
        <Modal title={editingRecipeId ? 'Edit Recipe' : 'New Recipe'} onClose={closeRecipeEditor}>
          <div className="modal-form">
            <label className="form-field">
              <span>Title</span>
              <input
                type="text"
                value={recipeDraft.title}
                onChange={(event) => setRecipeDraft({ ...recipeDraft, title: event.target.value })}
              />
            </label>

            <label className="form-field">
              <span>Summary</span>
              <textarea
                value={recipeDraft.summary}
                onChange={(event) => setRecipeDraft({ ...recipeDraft, summary: event.target.value })}
                rows={3}
              />
            </label>

            <div className="two-up">
              <label className="form-field">
                <span>Owner</span>
                <input
                  type="text"
                  value={recipeDraft.familyOwner}
                  onChange={(event) => setRecipeDraft({ ...recipeDraft, familyOwner: event.target.value })}
                />
              </label>
              <label className="form-field">
                <span>Tags</span>
                <input
                  type="text"
                  value={recipeDraft.tagsText}
                  onChange={(event) => setRecipeDraft({ ...recipeDraft, tagsText: event.target.value })}
                  placeholder="Soup, Weeknight, Imported"
                />
              </label>
            </div>

            <label className="checkbox-row">
              <input
                type="checkbox"
                checked={recipeDraft.isFavorite}
                onChange={(event) => setRecipeDraft({ ...recipeDraft, isFavorite: event.target.checked })}
              />
              Favorite recipe
            </label>

            <section className="editor-section">
              <div className="section-heading compact">
                <h3>Ingredients</h3>
                <button
                  className="ghost-button small"
                  onClick={() =>
                    setRecipeDraft({
                      ...recipeDraft,
                      ingredients: [...recipeDraft.ingredients, { id: createId(), amount: '', unit: '', name: '' }],
                    })
                  }
                >
                  Add Ingredient
                </button>
              </div>
              <div className="detail-stack">
                {recipeDraft.ingredients.map((ingredient, index) => (
                  <div className="ingredient-row" key={ingredient.id}>
                    <input
                      type="text"
                      placeholder="Amount"
                      value={ingredient.amount}
                      onChange={(event) =>
                        setRecipeDraft({
                          ...recipeDraft,
                          ingredients: updateArrayItem(recipeDraft.ingredients, index, {
                            ...ingredient,
                            amount: event.target.value,
                          }),
                        })
                      }
                    />
                    <input
                      type="text"
                      placeholder="Unit"
                      value={ingredient.unit}
                      onChange={(event) =>
                        setRecipeDraft({
                          ...recipeDraft,
                          ingredients: updateArrayItem(recipeDraft.ingredients, index, {
                            ...ingredient,
                            unit: event.target.value,
                          }),
                        })
                      }
                    />
                    <input
                      type="text"
                      placeholder="Ingredient"
                      value={ingredient.name}
                      onChange={(event) =>
                        setRecipeDraft({
                          ...recipeDraft,
                          ingredients: updateArrayItem(recipeDraft.ingredients, index, {
                            ...ingredient,
                            name: event.target.value,
                          }),
                        })
                      }
                    />
                    <button
                      className="danger-button small"
                      onClick={() =>
                        setRecipeDraft({
                          ...recipeDraft,
                          ingredients: recipeDraft.ingredients.filter((item) => item.id !== ingredient.id),
                        })
                      }
                    >
                      Remove
                    </button>
                  </div>
                ))}
              </div>
            </section>

            <section className="editor-section">
              <div className="section-heading compact">
                <h3>Steps</h3>
                <button
                  className="ghost-button small"
                  onClick={() =>
                    setRecipeDraft({
                      ...recipeDraft,
                      steps: [...recipeDraft.steps, { id: createId(), title: '', instruction: '' }],
                    })
                  }
                >
                  Add Step
                </button>
              </div>
              <div className="detail-stack">
                {recipeDraft.steps.map((step, index) => (
                  <div className="step-editor-card" key={step.id}>
                    <input
                      type="text"
                      placeholder="Step title"
                      value={step.title}
                      onChange={(event) =>
                        setRecipeDraft({
                          ...recipeDraft,
                          steps: updateArrayItem(recipeDraft.steps, index, {
                            ...step,
                            title: event.target.value,
                          }),
                        })
                      }
                    />
                    <textarea
                      placeholder="Instruction"
                      rows={3}
                      value={step.instruction}
                      onChange={(event) =>
                        setRecipeDraft({
                          ...recipeDraft,
                          steps: updateArrayItem(recipeDraft.steps, index, {
                            ...step,
                            instruction: event.target.value,
                          }),
                        })
                      }
                    />
                    <button
                      className="danger-button small"
                      onClick={() =>
                        setRecipeDraft({
                          ...recipeDraft,
                          steps: recipeDraft.steps.filter((item) => item.id !== step.id),
                        })
                      }
                    >
                      Remove Step
                    </button>
                  </div>
                ))}
              </div>
            </section>

            <div className="button-row wrap end">
              <button className="ghost-button" onClick={closeRecipeEditor}>
                Cancel
              </button>
              <button className="primary-button" onClick={() => void saveRecipeDraft()}>
                Save Recipe
              </button>
            </div>
          </div>
        </Modal>
      ) : null}

      {logDraft && loggingRecipeId ? (
        <Modal title="Log Cook" onClose={closeLogEditor}>
          <div className="modal-form">
            <div className="two-up">
              <label className="form-field">
                <span>Cooked On</span>
                <input
                  type="datetime-local"
                  value={logDraft.cookedOn}
                  onChange={(event) => setLogDraft({ ...logDraft, cookedOn: event.target.value })}
                />
              </label>

              <label className="form-field">
                <span>Cook Name</span>
                <input
                  type="text"
                  value={logDraft.cookName}
                  onChange={(event) => setLogDraft({ ...logDraft, cookName: event.target.value })}
                />
              </label>
            </div>

            <div className="two-up">
              <label className="form-field">
                <span>Rating</span>
                <input
                  type="number"
                  min={1}
                  max={5}
                  value={logDraft.rating}
                  onChange={(event) => setLogDraft({ ...logDraft, rating: Number(event.target.value) })}
                />
              </label>
              <label className="form-field">
                <span>Mood</span>
                <input
                  type="text"
                  value={logDraft.mood}
                  onChange={(event) => setLogDraft({ ...logDraft, mood: event.target.value })}
                />
              </label>
            </div>

            <label className="form-field">
              <span>Tweak Summary</span>
              <textarea
                rows={2}
                value={logDraft.tweakSummary}
                onChange={(event) => setLogDraft({ ...logDraft, tweakSummary: event.target.value })}
              />
            </label>

            <label className="form-field">
              <span>Notes</span>
              <textarea
                rows={3}
                value={logDraft.notes}
                onChange={(event) => setLogDraft({ ...logDraft, notes: event.target.value })}
              />
            </label>

            <label className="form-field">
              <span>Next Time</span>
              <textarea
                rows={2}
                value={logDraft.nextTimeNote}
                onChange={(event) => setLogDraft({ ...logDraft, nextTimeNote: event.target.value })}
              />
            </label>

            <section className="editor-section">
              <h3>Step Observations</h3>
              <div className="detail-stack">
                {logDraft.observations.map((observation, index) => (
                  <label className="form-field" key={observation.id}>
                    <span>{observation.stepTitle}</span>
                    <textarea
                      rows={2}
                      value={observation.note}
                      onChange={(event) =>
                        setLogDraft({
                          ...logDraft,
                          observations: updateArrayItem(logDraft.observations, index, {
                            ...observation,
                            note: event.target.value,
                          }),
                        })
                      }
                    />
                  </label>
                ))}
              </div>
            </section>

            <section className="editor-section">
              <div className="section-heading compact">
                <h3>Photos</h3>
                <input type="file" accept="image/*" capture="environment" multiple onChange={(event) => void handlePhotoSelection(event)} />
              </div>
              {logDraft.photos.length > 0 ? (
                <div className="photo-grid">
                  {logDraft.photos.map((photo, index) => (
                    <figure key={photo.id} className="photo-card">
                      <img src={photo.imageData} alt={photo.caption} />
                      <figcaption>
                        <input
                          type="text"
                          value={photo.stage}
                          onChange={(event) =>
                            setLogDraft({
                              ...logDraft,
                              photos: updateArrayItem(logDraft.photos, index, { ...photo, stage: event.target.value }),
                            })
                          }
                          placeholder="Stage"
                        />
                        <input
                          type="text"
                          value={photo.caption}
                          onChange={(event) =>
                            setLogDraft({
                              ...logDraft,
                              photos: updateArrayItem(logDraft.photos, index, { ...photo, caption: event.target.value }),
                            })
                          }
                          placeholder="Caption"
                        />
                        <button
                          className="danger-button small"
                          onClick={() =>
                            setLogDraft({
                              ...logDraft,
                              photos: logDraft.photos.filter((item) => item.id !== photo.id),
                            })
                          }
                        >
                          Remove Photo
                        </button>
                      </figcaption>
                    </figure>
                  ))}
                </div>
              ) : (
                <p className="section-subtitle">No photos attached yet.</p>
              )}
            </section>

            <div className="button-row wrap end">
              <button className="ghost-button" onClick={closeLogEditor}>
                Cancel
              </button>
              <button className="primary-button" onClick={() => void saveLogDraft()}>
                Save Cook Log
              </button>
            </div>
          </div>
        </Modal>
      ) : null}

      {selectedRecipe && scaleState?.recipeId === selectedRecipe.id ? (
        <Modal
          title="Scale Recipe"
          onClose={() => {
            setScaleState(null)
            window.location.hash = `/recipes/${selectedRecipe.id}`
          }}
        >
          <ScaleEditor
            recipe={selectedRecipe}
            currentFactor={scaleState.factor}
            onApplyMultiplier={applyScaleMultiplier}
            onApplyIngredientAmount={applyScaleByIngredient}
            onReset={() => {
              setScaleState(null)
              window.location.hash = `/recipes/${selectedRecipe.id}`
            }}
          />
        </Modal>
      ) : null}

      {importState.isOpen ? (
        <Modal
          title="Import Recipe from URL"
          onClose={() => {
            setImportState({ isOpen: false, url: '', isLoading: false, message: null, importedRecipe: null })
            window.location.hash = '/recipes'
          }}
        >
          <div className="modal-form">
            <label className="form-field">
              <span>Recipe URL</span>
              <input
                type="url"
                placeholder="https://www.allrecipes.com/..."
                value={importState.url}
                onChange={(event) => setImportState({ ...importState, url: event.target.value, importedRecipe: null })}
              />
            </label>
            <p className="section-subtitle">
              Browser import works best for sites that expose recipe schema and allow cross-origin fetches.
            </p>
            {importState.importedRecipe ? (
              <section className="detail-section">
                <h3>Preview</h3>
                <div className="profile-meta">
                  <span>Source</span>
                  <strong>{importState.importedRecipe.familyOwner}</strong>
                </div>
                <div className="profile-meta">
                  <span>Title</span>
                  <strong>{importState.importedRecipe.title}</strong>
                </div>
                {importState.importedRecipe.summary ? <p>{importState.importedRecipe.summary}</p> : null}
                <div className="meta-pill-row">
                  <span className="meta-pill">{importState.importedRecipe.ingredients.length} ingredients</span>
                  <span className="meta-pill">{importState.importedRecipe.steps.length} steps</span>
                  {importState.importedRecipe.tags.map((tag) => (
                    <span key={tag} className="meta-pill">
                      {tag}
                    </span>
                  ))}
                </div>
              </section>
            ) : null}
            {importState.message ? <p className="message error">{importState.message}</p> : null}
            <div className="button-row wrap end">
              <button
                className="ghost-button"
                onClick={() => {
                  setImportState({ isOpen: false, url: '', isLoading: false, message: null, importedRecipe: null })
                  window.location.hash = '/recipes'
                }}
              >
                Cancel
              </button>
              <button className="ghost-button" onClick={() => void fetchRecipeImportPreview()} disabled={importState.isLoading}>
                {importState.isLoading ? 'Fetching…' : 'Fetch Recipe'}
              </button>
              <button className="primary-button" onClick={saveImportedRecipePreview} disabled={!importState.importedRecipe}>
                Import
              </button>
            </div>
          </div>
        </Modal>
      ) : null}

      {selectedLog ? (
        <Modal title="Cook Log" onClose={closeCookLogDetail}>
          <CookLogDetail
            recipeTitle={selectedLog.recipeTitle}
            log={selectedLog.log}
            onDelete={() => {
              void deleteLog(selectedLog.recipeId, selectedLog.log.id)
              setSelectedLog(null)
            }}
          />
        </Modal>
      ) : null}

      {pendingConflict ? (
        <Modal title="Sync Conflict" onClose={() => setPendingConflict(null)}>
          <div className="modal-form">
            <p className="message error">{pendingConflict.message}</p>
            <div className="two-up">
              <section className="detail-section">
                <h3>Web Changes</h3>
                <p className="section-subtitle">Updated {formatDate(pendingConflict.localSnapshot.updatedAt)}</p>
                <p>{pendingConflict.localSnapshot.recipes.length} recipes</p>
              </section>
              <section className="detail-section">
                <h3>Shared Version</h3>
                <p className="section-subtitle">Updated {formatDate(pendingConflict.remoteSnapshot.updatedAt)}</p>
                <p>{pendingConflict.remoteSnapshot.recipes.length} recipes</p>
              </section>
            </div>
            <div className="button-row wrap end">
              <button className="ghost-button" onClick={() => setPendingConflict(null)}>
                Cancel
              </button>
              <button className="danger-button" onClick={() => void resolveConflictUsingRemote()}>
                Use Shared Version
              </button>
              <button className="primary-button" onClick={() => void resolveConflictKeepingLocal()}>
                Keep Web Changes
              </button>
            </div>
          </div>
        </Modal>
      ) : null}
    </div>
  )
}

function ScaleEditor({
  recipe,
  currentFactor,
  onApplyMultiplier,
  onApplyIngredientAmount,
  onReset,
}: {
  recipe: RecipeSnapshot
  currentFactor: number
  onApplyMultiplier: (multiplier: number) => void
  onApplyIngredientAmount: (ingredientId: string, newAmountText: string) => void
  onReset: () => void
}) {
  const [multiplierText, setMultiplierText] = useState(String(currentFactor))
  const [ingredientId, setIngredientId] = useState(recipe.ingredients[0]?.id ?? '')
  const [targetAmount, setTargetAmount] = useState('')

  return (
    <div className="modal-form">
      <section className="detail-section">
        <h3>Method 1: Multiply the whole recipe</h3>
        <div className="inline-form">
          <input type="text" value={multiplierText} onChange={(event) => setMultiplierText(event.target.value)} placeholder="2" />
          <button className="primary-button" onClick={() => onApplyMultiplier(Number(multiplierText) || 1)}>
            Apply Multiplier
          </button>
        </div>
      </section>

      <section className="detail-section">
        <h3>Method 2: Match one ingredient</h3>
        <div className="inline-form stacked-mobile">
          <select value={ingredientId} onChange={(event) => setIngredientId(event.target.value)}>
            {recipe.ingredients.map((ingredient) => (
              <option key={ingredient.id} value={ingredient.id}>
                {ingredient.name} ({ingredient.amount})
              </option>
            ))}
          </select>
          <input
            type="text"
            value={targetAmount}
            onChange={(event) => setTargetAmount(event.target.value)}
            placeholder="New amount, e.g. 3 or 1 1/2"
          />
          <button className="primary-button" onClick={() => onApplyIngredientAmount(ingredientId, targetAmount)}>
            Match Ingredient
          </button>
        </div>
      </section>

      <div className="button-row wrap end">
        <button className="ghost-button" onClick={onReset}>
          Reset Scale
        </button>
      </div>
    </div>
  )
}

function CookLogDetail({
  recipeTitle,
  log,
  onDelete,
}: {
  recipeTitle: string
  log: CookLogSnapshot
  onDelete: () => void
}) {
  return (
    <div className="modal-form">
      <section className="detail-section">
        <h3>{recipeTitle}</h3>
        <p className="section-subtitle">
          {log.cookName} cooked this on {formatDate(log.cookedOn)}
        </p>
        <div className="meta-pill-row">
          <span className="meta-pill">{renderStars(log.rating)}</span>
          {log.mood ? <span className="meta-pill">{log.mood}</span> : null}
        </div>
      </section>

      {log.tweakSummary ? (
        <section className="detail-section">
          <h3>What Changed</h3>
          <p>{log.tweakSummary}</p>
        </section>
      ) : null}

      <section className="detail-section">
        <h3>Notes</h3>
        {log.notes ? <p>{log.notes}</p> : <p className="section-subtitle">No notes recorded.</p>}
        {log.nextTimeNote ? <p><strong>Next time:</strong> {log.nextTimeNote}</p> : null}
      </section>

      <section className="detail-section">
        <h3>Photo Timeline</h3>
        {log.photos.length ? (
          <div className="photo-grid">
            {log.photos.map((photo) => (
              <figure key={photo.id} className="photo-card">
                {photo.imageData ? <img src={decodePhotoSource(photo)} alt={photo.caption || photo.stage} /> : null}
                <figcaption>
                  <strong>{photo.stage}</strong>
                  <span>{photo.caption}</span>
                </figcaption>
              </figure>
            ))}
          </div>
        ) : (
          <p className="section-subtitle">No photos attached.</p>
        )}
      </section>

      <section className="detail-section">
        <h3>Step Observations</h3>
        {log.observations.length ? (
          <ul className="stack-list inset">
            {log.observations.map((observation) => (
              <li key={observation.id}>
                <strong>{observation.stepTitle}</strong> {observation.note}
              </li>
            ))}
          </ul>
        ) : (
          <p className="section-subtitle">No step observations yet.</p>
        )}
      </section>

      <div className="button-row wrap end">
        <button className="danger-button" onClick={onDelete}>
          Delete Log
        </button>
      </div>
    </div>
  )
}

function Modal({
  title,
  children,
  onClose,
}: {
  title: string
  children: ReactNode
  onClose: () => void
}) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-card" onClick={(event) => event.stopPropagation()}>
        <div className="modal-header">
          <h2>{title}</h2>
          <button className="ghost-button small" onClick={onClose}>
            Close
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}

function EmptyState({ title, subtitle, compact = false }: { title: string; subtitle: string; compact?: boolean }) {
  return (
    <div className={`empty-state ${compact ? 'is-compact' : ''}`}>
      <h2>{title}</h2>
      <p>{subtitle}</p>
    </div>
  )
}

function cloneCookbook(snapshot: CookbookSnapshot): CookbookSnapshot {
  return JSON.parse(JSON.stringify(snapshot)) as CookbookSnapshot
}

function makeEmptyCookbook(ownerName: string): CookbookSnapshot {
  return {
    title: 'Family Cookbook',
    ownerName,
    updatedAt: new Date().toISOString(),
    recipes: [],
    shoppingItems: [],
  }
}

function makeEmptyRecipeDraft(defaultOwner: string): RecipeDraft {
  return {
    title: '',
    summary: '',
    familyOwner: defaultOwner,
    isFavorite: false,
    tagsText: '',
    ingredients: [{ id: createId(), amount: '', unit: '', name: '' }],
    steps: [{ id: createId(), title: '', instruction: '' }],
  }
}

function recipeToDraft(recipe: RecipeSnapshot): RecipeDraft {
  return {
    title: recipe.title,
    summary: recipe.summary,
    familyOwner: recipe.familyOwner,
    isFavorite: recipe.isFavorite,
    tagsText: recipe.tags.join(', '),
    ingredients: recipe.ingredients.map((ingredient) => {
      const components = splitIngredientAmount(ingredient.amount)
      return {
        id: ingredient.id,
        amount: components.amount,
        unit: components.unit,
        name: ingredient.name,
      }
    }),
    steps: recipe.steps.map((step) => ({
      id: step.id,
      title: step.title,
      instruction: step.instruction,
    })),
  }
}

function draftToRecipe(draft: RecipeDraft, existingRecipe: RecipeSnapshot | null): RecipeSnapshot {
  const now = new Date().toISOString()

  return {
    id: existingRecipe?.id ?? createId(),
    title: draft.title.trim(),
    summary: draft.summary.trim(),
    familyOwner: draft.familyOwner.trim() || 'Family',
    isFavorite: draft.isFavorite,
    tags: draft.tagsText
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean),
    sortOrder: existingRecipe?.sortOrder ?? 0,
    createdAt: existingRecipe?.createdAt ?? now,
    updatedAt: now,
    ingredients: draft.ingredients
      .filter((ingredient) => ingredient.name.trim())
      .map((ingredient, index) => ({
        id: ingredient.id,
        amount: combineIngredientAmount(ingredient.amount, ingredient.unit),
        name: ingredient.name.trim(),
        sortOrder: index,
      })),
    steps: draft.steps
      .filter((step) => step.title.trim() || step.instruction.trim())
      .map((step, index) => ({
        id: step.id,
        title: step.title.trim() || `Step ${index + 1}`,
        instruction: step.instruction.trim(),
        sortOrder: index,
      })),
    logs: existingRecipe?.logs ?? [],
  }
}

function makeEmptyLogDraft(recipe: RecipeSnapshot, cookName: string): LogDraft {
  return {
    cookedOn: toDateTimeInputValue(new Date()),
    cookName,
    rating: 4,
    mood: 'Happy',
    tweakSummary: '',
    notes: '',
    nextTimeNote: '',
    observations: recipe.steps.map((step) => ({
      id: createId(),
      stepTitle: step.title,
      note: '',
    })),
    photos: [],
  }
}

function draftToCookLog(draft: LogDraft): CookLogSnapshot {
  const now = new Date().toISOString()
  return {
    id: createId(),
    cookedOn: new Date(draft.cookedOn).toISOString(),
    cookName: draft.cookName.trim() || 'Cook',
    rating: draft.rating,
    mood: draft.mood.trim(),
    tweakSummary: draft.tweakSummary.trim(),
    notes: draft.notes.trim(),
    nextTimeNote: draft.nextTimeNote.trim(),
    createdAt: now,
    updatedAt: now,
    photos: draft.photos.map((photo, index) => ({
      id: photo.id,
      stage: photo.stage,
      caption: photo.caption,
      imageData: stripDataUrlPrefix(photo.imageData),
      sortOrder: index,
    })),
    observations: draft.observations
      .filter((observation) => observation.note.trim())
      .map((observation, index) => ({
        id: observation.id,
        stepTitle: observation.stepTitle,
        note: observation.note.trim(),
        sortOrder: index,
      })),
  }
}

function compareRecipes(left: RecipeSnapshot, right: RecipeSnapshot, sort: RecipeSort) {
  switch (sort) {
    case 'owner': {
      const ownerOrder = left.familyOwner.localeCompare(right.familyOwner, undefined, { sensitivity: 'base' })
      return ownerOrder || left.title.localeCompare(right.title, undefined, { sensitivity: 'base' })
    }
    case 'recent': {
      const leftDate = latestRecipeActivityDate(left).getTime()
      const rightDate = latestRecipeActivityDate(right).getTime()
      return rightDate - leftDate || left.title.localeCompare(right.title, undefined, { sensitivity: 'base' })
    }
    case 'title':
    default:
      return left.title.localeCompare(right.title, undefined, { sensitivity: 'base' })
  }
}

function latestRecipeActivityDate(recipe: RecipeSnapshot) {
  const latestLog = recipe.logs
    .map((log) => new Date(log.cookedOn))
    .sort((left, right) => right.getTime() - left.getTime())[0]

  return latestLog ?? new Date(recipe.updatedAt)
}

function latestCookSummary(recipe: RecipeSnapshot) {
  const latestLog = [...recipe.logs].sort(
    (left, right) => new Date(right.cookedOn).getTime() - new Date(left.cookedOn).getTime(),
  )[0]

  if (!latestLog) {
    return ''
  }

  return `${latestLog.cookName} last cooked this and rated it ${latestLog.rating}/5`
}

function splitIngredientAmount(amountText: string) {
  const trimmed = amountText.trim()
  if (!trimmed) {
    return { amount: '', unit: '' }
  }

  const amount = extractLeadingAmountToken(trimmed)
  if (!amount) {
    return { amount: trimmed, unit: '' }
  }

  return {
    amount,
    unit: trimmed.slice(amount.length).trim(),
  }
}

function combineIngredientAmount(amount: string, unit: string) {
  return [amount.trim(), unit.trim()].filter(Boolean).join(' ')
}

function sortShoppingItems(items: ShoppingListItemSnapshot[]) {
  return [...items].sort((left, right) => {
    if (left.isChecked !== right.isChecked) {
      return Number(left.isChecked) - Number(right.isChecked)
    }

    return left.sortOrder - right.sortOrder
  })
}

function getNextShoppingSortOrder(items: ShoppingListItemSnapshot[]) {
  return items.length ? Math.max(...items.map((item) => item.sortOrder)) + 1 : 0
}

function updateArrayItem<T>(items: T[], index: number, nextValue: T) {
  return items.map((item, itemIndex) => (itemIndex === index ? nextValue : item))
}

function createId() {
  return crypto.randomUUID()
}

function normaliseCookbookSnapshot(payload: unknown): CookbookSnapshot {
  const snapshot = payload as CookbookSnapshot
  return {
    ...snapshot,
    shoppingItems: snapshot.shoppingItems ?? [],
    recipes: (snapshot.recipes ?? []).map((recipe) => ({
      ...recipe,
      logs: recipe.logs ?? [],
      ingredients: recipe.ingredients ?? [],
      steps: recipe.steps ?? [],
    })),
  }
}

async function fetchRemoteCookbook(): Promise<{ snapshot: CookbookSnapshot | null; error: string | null }> {
  if (!supabase) {
    return { snapshot: null, error: 'Supabase is not configured' }
  }

  const { data, error } = await supabase
    .from('shared_cookbooks')
    .select('payload, updated_at')
    .eq('slug', SHARED_COOKBOOK_SLUG)
    .maybeSingle()

  if (error) {
    return { snapshot: null, error: error.message }
  }

  if (!data?.payload) {
    return { snapshot: null, error: null }
  }

  return { snapshot: normaliseCookbookSnapshot(data.payload), error: null }
}

function isRemoteNewer(remote: CookbookSnapshot, local: CookbookSnapshot) {
  return new Date(remote.updatedAt).getTime() - new Date(local.updatedAt).getTime() > 1000
}

function loadCachedCookbook() {
  try {
    const rawValue = localStorage.getItem(OFFLINE_COOKBOOK_KEY)
    return rawValue ? normaliseCookbookSnapshot(JSON.parse(rawValue)) : null
  } catch {
    return null
  }
}

function loadPendingCookbook() {
  try {
    const rawValue = localStorage.getItem(PENDING_COOKBOOK_KEY)
    return rawValue ? normaliseCookbookSnapshot(JSON.parse(rawValue)) : null
  } catch {
    return null
  }
}

async function loadCookbookSnapshot(key: string) {
  const indexedSnapshot = await readIndexedCookbookSnapshot(key)
  if (indexedSnapshot) {
    return indexedSnapshot
  }

  try {
    const rawValue = localStorage.getItem(key)
    return rawValue ? normaliseCookbookSnapshot(JSON.parse(rawValue)) : null
  } catch {
    return null
  }
}

async function persistCookbookSnapshot(key: string, snapshot: CookbookSnapshot) {
  const rawValue = JSON.stringify(snapshot)
  localStorage.setItem(key, rawValue)

  try {
    const database = await openSnapshotDatabase()
    await runSnapshotTransaction(database, 'readwrite', (store) => {
      store.put(rawValue, key)
    })
  } catch {
    // localStorage remains the compatibility fallback when IndexedDB is unavailable.
  }
}

async function removeCookbookSnapshot(key: string) {
  localStorage.removeItem(key)

  try {
    const database = await openSnapshotDatabase()
    await runSnapshotTransaction(database, 'readwrite', (store) => {
      store.delete(key)
    })
  } catch {
    // Nothing else to do; localStorage has already been cleared.
  }
}

async function readIndexedCookbookSnapshot(key: string) {
  try {
    const database = await openSnapshotDatabase()
    const rawValue = await new Promise<string | undefined>((resolve, reject) => {
      const transaction = database.transaction(SNAPSHOT_STORE_NAME, 'readonly')
      const request = transaction.objectStore(SNAPSHOT_STORE_NAME).get(key)
      request.onsuccess = () => resolve(typeof request.result === 'string' ? request.result : undefined)
      request.onerror = () => reject(request.error)
    })

    return rawValue ? normaliseCookbookSnapshot(JSON.parse(rawValue)) : null
  } catch {
    return null
  }
}

function openSnapshotDatabase() {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(SNAPSHOT_DB_NAME, 1)
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(SNAPSHOT_STORE_NAME)) {
        request.result.createObjectStore(SNAPSHOT_STORE_NAME)
      }
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

function runSnapshotTransaction(
  database: IDBDatabase,
  mode: IDBTransactionMode,
  operation: (store: IDBObjectStore) => void,
) {
  return new Promise<void>((resolve, reject) => {
    const transaction = database.transaction(SNAPSHOT_STORE_NAME, mode)
    transaction.oncomplete = () => resolve()
    transaction.onerror = () => reject(transaction.error)
    operation(transaction.objectStore(SNAPSHOT_STORE_NAME))
  })
}

function parseRoute() {
  const parts = window.location.hash.replace(/^#\/?/, '').split('/').filter(Boolean)
  const tab = parts[0] as TabKey | undefined

  if (tab === 'activity' || tab === 'shopping' || tab === 'profile') {
    return { tab, recipeId: null, logId: null, action: null }
  }

  if (tab === 'recipes') {
    if (parts[1] === 'new' || parts[1] === 'import') {
      return {
        tab,
        recipeId: null,
        logId: null,
        action: parts[1],
      }
    }

    const recipeId = parts[1] ?? null
    const action = parts[2] === 'logs' ? 'log-detail' : parts[2] ?? null

    return {
      tab,
      recipeId,
      logId: parts[2] === 'logs' ? parts[3] ?? null : null,
      action,
    }
  }

  return { tab: 'recipes' as TabKey, recipeId: null, logId: null, action: null }
}

function toDateTimeInputValue(date: Date) {
  const iso = date.toISOString()
  return iso.slice(0, 16)
}

function decodePhotoSource(photo: CookPhotoSnapshot) {
  if (!photo.imageData) {
    return ''
  }

  if (photo.imageData.startsWith('data:')) {
    return photo.imageData
  }

  return `data:image/jpeg;base64,${photo.imageData}`
}

function stripDataUrlPrefix(imageData: string) {
  const marker = 'base64,'
  const markerIndex = imageData.indexOf(marker)
  if (markerIndex === -1) {
    return imageData
  }

  return imageData.slice(markerIndex + marker.length)
}

function scaleIngredientAmount(amountText: string, factor: number) {
  const numericPortion = parseLeadingAmount(amountText)
  if (!numericPortion) {
    return amountText
  }

  const scaled = numericPortion * factor
  return amountText.replace(extractLeadingAmountToken(amountText), formatScaledAmount(scaled))
}

function parseLeadingAmount(amountText: string) {
  const token = extractLeadingAmountToken(amountText)
  if (!token) {
    return null
  }

  const normalised = token
    .replaceAll('¼', '1/4')
    .replaceAll('½', '1/2')
    .replaceAll('¾', '3/4')
    .replaceAll('⅓', '1/3')
    .replaceAll('⅔', '2/3')
    .trim()

  if (normalised.includes(' ')) {
    const [whole, fraction] = normalised.split(' ')
    const wholeValue = Number(whole)
    const fractionValue = parseFraction(fraction)
    if (!Number.isNaN(wholeValue) && fractionValue) {
      return wholeValue + fractionValue
    }
  }

  const fractionValue = parseFraction(normalised)
  if (fractionValue) {
    return fractionValue
  }

  const numericValue = Number(normalised)
  return Number.isFinite(numericValue) ? numericValue : null
}

function parseFraction(text: string) {
  if (!text.includes('/')) {
    return null
  }

  const [numerator, denominator] = text.split('/')
  const numeratorValue = Number(numerator)
  const denominatorValue = Number(denominator)
  if (!Number.isFinite(numeratorValue) || !Number.isFinite(denominatorValue) || denominatorValue === 0) {
    return null
  }

  return numeratorValue / denominatorValue
}

function extractLeadingAmountToken(amountText: string) {
  const match = amountText.trim().match(/^([0-9.,/ ]+|[¼½¾⅓⅔])/)
  return match?.[0]?.trim() ?? ''
}

function formatScaledAmount(value: number) {
  const rounded = Math.round(value * 100) / 100
  const whole = Math.floor(rounded)
  const fraction = rounded - whole

  const fractionMap: Array<[number, string]> = [
    [0.25, '1/4'],
    [0.333, '1/3'],
    [0.5, '1/2'],
    [0.667, '2/3'],
    [0.75, '3/4'],
  ]

  const matchedFraction = fractionMap.find(([candidate]) => Math.abs(candidate - fraction) < 0.03)
  if (matchedFraction) {
    if (whole === 0) {
      return matchedFraction[1]
    }

    return `${whole} ${matchedFraction[1]}`
  }

  if (Math.abs(rounded - Math.round(rounded)) < 0.01) {
    return String(Math.round(rounded))
  }

  return rounded.toFixed(2).replace(/\.00$/, '')
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function formatRelativeDate(value: string) {
  const difference = Date.now() - new Date(value).getTime()
  const minutes = Math.round(difference / 60000)

  if (minutes < 1) {
    return 'just now'
  }

  if (minutes < 60) {
    return `${minutes}m ago`
  }

  const hours = Math.round(minutes / 60)
  if (hours < 24) {
    return `${hours}h ago`
  }

  const days = Math.round(hours / 24)
  return `${days}d ago`
}

function renderStars(rating: number) {
  return '★'.repeat(Math.max(0, rating)) || '—'
}

async function readFileAsDataUrl(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(new Error('Could not read image file.'))
    reader.onload = () => resolve(String(reader.result))
    reader.readAsDataURL(file)
  })
}

function normalizeRecipeUrl(value: string) {
  const trimmed = value.trim()
  if (!trimmed) {
    return null
  }

  try {
    const directUrl = new URL(trimmed)
    return directUrl.toString()
  } catch {
    try {
      return new URL(`https://${trimmed}`).toString()
    } catch {
      return null
    }
  }
}

function parseRecipeFromHtml(url: string, html: string): RecipeSnapshot {
  const document = new DOMParser().parseFromString(html, 'text/html')
  const recipeNodes = Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
  const recipes = recipeNodes
    .flatMap((node) => {
      try {
        const value = JSON.parse(node.textContent ?? '')
        return flattenJsonLdRecipeCandidates(value)
      } catch {
        return []
      }
    })
    .filter((item) => isRecipeType(item['@type']))

  const recipeData = recipes[0]
  if (!recipeData) {
    throw new Error('No recipe schema was found on that page.')
  }

  const hostname = new URL(url).hostname.replace('www.', '')
  const ingredients = ensureArray(recipeData.recipeIngredient).map((item, index) => ({
    id: createId(),
    amount: parseImportedAmount(String(item)),
    name: parseImportedIngredientName(String(item)),
    sortOrder: index,
  }))
  const steps = parseImportedSteps(recipeData.recipeInstructions)

  return {
    id: createId(),
    title: String(recipeData.name ?? 'Imported Recipe'),
    summary: String(recipeData.description ?? ''),
    familyOwner: hostname,
    isFavorite: false,
    tags: ['Imported', hostname],
    sortOrder: 0,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    ingredients,
    steps,
    logs: [],
  }
}

function flattenJsonLdRecipeCandidates(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) {
    return value.flatMap(flattenJsonLdRecipeCandidates)
  }

  if (typeof value !== 'object' || value === null) {
    return []
  }

  const record = value as Record<string, unknown>
  return [
    record,
    ...Object.values(record).flatMap((child) => {
      if (typeof child === 'object' && child !== null) {
        return flattenJsonLdRecipeCandidates(child)
      }

      return []
    }),
  ]
}

function isRecipeType(value: unknown) {
  if (Array.isArray(value)) {
    return value.some(isRecipeType)
  }

  return typeof value === 'string' && value.toLowerCase().includes('recipe')
}

function ensureArray(value: unknown) {
  if (Array.isArray(value)) {
    return value
  }

  if (value == null) {
    return []
  }

  return [value]
}

function parseImportedSteps(value: unknown): RecipeStepSnapshot[] {
  return ensureArray(value).flatMap((item, index) => {
    if (typeof item === 'string') {
      return [
        {
          id: createId(),
          title: `Step ${index + 1}`,
          instruction: item,
          sortOrder: index,
        },
      ]
    }

    if (typeof item === 'object' && item !== null) {
      const record = item as Record<string, unknown>
      if (record.itemListElement) {
        return parseImportedSteps(record.itemListElement)
      }

      return [
        {
          id: createId(),
          title: String(record.name ?? `Step ${index + 1}`),
          instruction: String(record.text ?? record.name ?? ''),
          sortOrder: index,
        },
      ]
    }

    return []
  })
}

function parseImportedAmount(value: string) {
  const token = extractLeadingAmountToken(value)
  return token || ''
}

function parseImportedIngredientName(value: string) {
  const amount = extractLeadingAmountToken(value)
  return value.replace(amount, '').trim()
}

export default App
