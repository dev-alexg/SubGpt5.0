<script setup lang="ts">
import { onMounted, ref } from 'vue'
import axios from 'axios'

const apiBase = import.meta.env.VITE_API_URL || ''
const health = ref<any>(null)
const error = ref<string>('')

onMounted(async () => {
  try {
    const { data } = await axios.get(`${apiBase}/api/health`)
    health.value = data
  } catch (e: any) {
    error.value = e?.message || 'Request failed'
  }
})
</script>

<template>
  <main style="font-family: system-ui; padding: 2rem; max-width: 720px; margin: auto;">
    <h1>Vue + Laravel</h1>
    <p>API base: <code>{{ import.meta.env.VITE_API_URL || '(same origin)' }}</code></p>

    <section v-if="health">
      <h2>Health</h2>
      <pre>{{ health }}</pre>
    </section>
    <section v-else-if="error">
      <h2>Ошибка запроса</h2>
      <pre>{{ error }}</pre>
    </section>
    <section v-else>
      <em>Загрузка...</em>
    </section>
  </main>
</template>

<style scoped>
pre {
  background: #f6f8fa;
  padding: 12px;
  border-radius: 8px;
  overflow: auto;
}
</style>
