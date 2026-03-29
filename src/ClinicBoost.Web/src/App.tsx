import { useEffect, useState } from 'react'

interface HealthStatus {
  status: string
  version: string
  timestamp: string
}

function App() {
  const [health, setHealth] = useState<HealthStatus | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch('/health')
      .then((res) => res.json())
      .then((data) => setHealth(data))
      .catch(() => setError('API no disponible'))
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-indigo-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-lg">CB</span>
            </div>
            <div>
              <h1 className="text-xl font-semibold text-gray-900">ClinicBoost</h1>
              <p className="text-xs text-gray-500">Revenue Recovery Layer</p>
            </div>
          </div>
          <span className="px-3 py-1 text-xs font-medium bg-amber-100 text-amber-800 rounded-full">
            Bloque 0 — Scaffolding
          </span>
        </div>
      </header>

      {/* Main */}
      <main className="max-w-4xl mx-auto px-4 py-12">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-gray-900 mb-3">
            Motor de Ingresos Automatizado
          </h2>
          <p className="text-gray-600 max-w-2xl mx-auto">
            Capa de recuperación de ingresos para clínicas de fisioterapia privadas.
            Automatiza llamadas perdidas, huecos de agenda, no-shows y reactivación de pacientes.
          </p>
        </div>

        {/* API Status Card */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6 mb-8">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Estado del API</h3>
          {error ? (
            <div className="flex items-center gap-2 text-red-600">
              <div className="w-3 h-3 bg-red-500 rounded-full" />
              <span>{error}</span>
            </div>
          ) : health ? (
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 bg-green-500 rounded-full animate-pulse" />
                <span className="text-green-700 font-medium">
                  {health.status}
                </span>
              </div>
              <p className="text-sm text-gray-500">
                Version: {health.version} | UTC: {health.timestamp}
              </p>
            </div>
          ) : (
            <div className="flex items-center gap-2 text-gray-400">
              <div className="w-3 h-3 bg-gray-300 rounded-full animate-pulse" />
              <span>Conectando...</span>
            </div>
          )}
        </div>

        {/* Feature Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {[
            { title: 'Flow 01 — Llamadas Perdidas', desc: 'WhatsApp automático tras llamada no contestada', block: 'Bloque 4' },
            { title: 'Flow 02 — Yield Management', desc: 'Detección y relleno de huecos de agenda', block: 'Bloque 5' },
            { title: 'Flow 03 — No-Shows', desc: 'Reagendado automático de citas no asistidas', block: 'Bloque 6' },
            { title: 'Flow 04 — Fuera de Horario', desc: 'Captura de leads fuera del horario de atención', block: 'Bloque 7' },
            { title: 'Flow 05 — NPS', desc: 'Encuestas de satisfacción post-sesión', block: 'Bloque 8' },
            { title: 'Flow 06 — Reactivación', desc: 'Campañas para pacientes inactivos', block: 'Bloque 9' },
          ].map((flow) => (
            <div
              key={flow.title}
              className="bg-white rounded-lg border border-gray-200 p-5 opacity-60"
            >
              <div className="flex items-center justify-between mb-2">
                <h4 className="font-medium text-gray-900">{flow.title}</h4>
                <span className="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded">
                  {flow.block}
                </span>
              </div>
              <p className="text-sm text-gray-500">{flow.desc}</p>
            </div>
          ))}
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-200 mt-16">
        <div className="max-w-7xl mx-auto px-4 py-6 text-center text-sm text-gray-400">
          ClinicBoost v0.1.0 — Bloque 0 Scaffolding
        </div>
      </footer>
    </div>
  )
}

export default App
