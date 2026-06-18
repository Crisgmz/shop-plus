# PRD — Landing Page Shop+

---

## 🤖 PROMPT PARA CREAR LA WEB

> Copiar/pegar este prompt en Claude / v0 / Lovable / Cursor / la IA que vayas a usar para generar la landing. El PRD completo está debajo del prompt como contexto.

```
Necesito que generes una landing page completa para "Shop+", un
sistema de Punto de Venta (POS) multi-sucursal para el mercado dominicano.
El PRD detallado está debajo de este prompt — léelo entero antes de empezar.

REQUISITOS TÉCNICOS:
- Stack: Astro 4+ con TypeScript, Tailwind CSS 3+, componentes en formato .astro
- Single page (todo en index.astro) con anchors para navegación interna
- Mobile-first, totalmente responsive (breakpoints 640/768/1024/1280)
- Performance: Lighthouse score 95+ en mobile, sin JS innecesario
- Imágenes: usar placeholders con dimensiones correctas (next/image style)
- Animaciones: solo Tailwind transitions, nada de Framer Motion / GSAP

REQUISITOS DE DISEÑO:
- Color primario: #0B5ED7 (azul brand)
- Color secundario / CTA: #22C55E (verde éxito)
- Fondos: blanco (#FFFFFF) y gris claro (#F8FAFC)
- Tipografía: Inter (Google Fonts), 16px base, 48px hero, 32px section headings
- Border radius: 12px en cards, 8px en botones
- Sombras: muy sutiles `0 4px 12px rgba(0,0,0,0.05)`
- Tono visual: limpio, profesional, NO startup-genérico. Referencias:
  Loyverse, Lightspeed, Square POS, Wilmaxsoft.
- Íconos: Lucide o Phosphor (consistencia obligatoria, no mezclar sets)

REQUISITOS DE CONTENIDO:
- Idioma: español dominicano (usar "vos" o "tú" consistentemente — el PRD
  usa "vos" en varios lugares; respetar ese tono).
- Headlines y bajadas EXACTAMENTE como están en el PRD (sección 3).
- NO inventes features que no estén en el PRD.
- Para testimonios, dejar placeholders con el formato del PRD pero marcar
  con `<!-- TODO: reemplazar con testimonio real -->`.
- Para "+XXX comercios", dejar `+50` como placeholder.

ESTRUCTURA OBLIGATORIA (en este orden):
1. Hero (3.1) — above-the-fold con CTAs
2. "Por qué Shop+" — 3 columnas (3.2)
3. Demo visual — placeholder para GIF/video (3.3)
4. Features detalladas — grid 3×2 (3.4)
5. "Cómo funciona" — 3 pasos (3.5)
6. Testimonios — 3 cards con placeholders (3.6)
7. Pricing — 3 planes (3.7)
8. FAQ — accordion con 8 preguntas (3.8)
9. CTA final — banner color brand (3.9)
10. Footer (3.10)

ENTREGABLES:
- Estructura completa del proyecto Astro
- index.astro funcional
- Componentes separados por sección si tiene sentido (Hero.astro,
  Features.astro, Pricing.astro, FAQ.astro, etc.)
- tailwind.config.mjs con los colores brand configurados
- README.md con `npm install && npm run dev` para arrancar local
- .gitignore correcto para Astro

LO QUE NO QUIERO:
- Carruseles con auto-play
- Newsletter forms o popups
- Live chat widgets
- Loaders dramáticos
- "Awesome", "Stunning", "Beautiful" o cualquier copywriting genérico
- Stock photos de gente sonriendo con headsets

CTAs PRIMARIOS (todos los botones "Empezar gratis" linkean a):
  https://app.busiposweb.com/registro

CTA "Iniciar sesión" linkea a:
  https://app.busiposweb.com/login

DOMINIO FINAL DE LA LANDING: busiposweb.com (raíz)
DOMINIO DE LA APP: app.busiposweb.com

Lee el PRD completo abajo, hacé preguntas si algo no está claro, y empezá
generando el proyecto Astro completo con todos los archivos.
```

---

## 1. Objetivo

Captar dueños de negocios retail / mayoristas en República Dominicana que necesiten un POS moderno, con cumplimiento DGII y operación multi-sucursal, y convertirlos en **signups** (`busiposweb.com/registro`).

**Métrica primaria:** tasa de conversión visitante → signup ≥ 4%.
**Métrica secundaria:** tiempo en página ≥ 1:30, scroll depth ≥ 60%.

---

## 2. Audiencia objetivo

| Perfil | Pain points | Trigger de búsqueda |
|---|---|---|
| Dueño de colmado / minimarket | Maneja todo en cuaderno, no sabe cuánto vende real. Pierde dinero por errores y mermas. | "sistema de facturación dominicana", "punto de venta colmado" |
| Tienda de repuestos / ferretería | Tiene 2-3 sucursales, no puede ver inventario unificado, los cajeros venden sin control. | "POS multi sucursal RD", "facturación DGII NCF" |
| Restaurante / comedor | Cajeros se confunden con NCF, devoluciones manuales, no sabe cuánto gana por plato. | "sistema fiscal restaurante DGII", "cierre Z fiscal" |
| Contador externo | Le piden 606, 607, IT-1 a fin de mes y no tiene los datos limpios. | "exportar 606 607 DGII excel" |

**Edad:** 30-55 · **Ubicación:** Santo Domingo, Santiago, La Romana, Punta Cana · **Dispositivo:** 60% mobile / 40% desktop.

---

## 3. Estructura de secciones (top-to-bottom)

### 3.1 Hero (above the fold)

```
┌────────────────────────────────────────────────────────┐
│  [Logo Shop+]                  Iniciar sesión │
├────────────────────────────────────────────────────────┤
│                                                        │
│    El POS dominicano que vende, factura y cumple      │
│    con la DGII sin que tu cajero tenga que pensarlo.   │
│                                                        │
│    NCF automático · Multi-sucursal · 606, 607, IT-1    │
│                                                        │
│    [  Empezar gratis ]   [ Ver demo en vivo ]          │
│                                                        │
│    ⭐ +XXX comercios activos · RD                       │
│                                                        │
│              [ Screenshot grande del POS ]             │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Headline (principal):** *"El POS dominicano que vende, factura y cumple con la DGII sin que tu cajero tenga que pensarlo."*

**Sub-headline:** "NCF automático, multi-sucursal, reportes 606/607/IT-1. Listo en 5 minutos."

**CTAs:**
- Primario: `Empezar gratis` → /registro
- Secundario: `Ver demo en vivo` → modal con video 60-90s del POS en acción

**Social proof inline:** "+XXX comercios usan Shop+ hoy" (placeholder hasta tener data real).

---

### 3.2 Bloque "Por qué Shop+" (3 columnas)

Tres beneficios fundamentales, no listas de features. Cada uno con un ícono custom + headline corto + 2 líneas.

| Ícono | Headline | Bajada |
|---|---|---|
| 🇩🇴 / RD$ | **Diseñado para RD** | NCF B01/B02/B14/B15/B16, ITBIS configurable, RNC validado, prefijos personalizables. |
| 🏪 | **Una empresa, N sucursales** | Cada cajero ve solo su caja. Tú ves todo en tiempo real desde el panel. |
| 📊 | **Cierre del día en 30 segundos** | Cierre Z fiscal sellado, 606/607/IT-1 exportables a TXT, reportes que tu contador entiende. |

---

### 3.3 Demo interactivo (o GIF/video)

GIF de 8-12 segundos del flujo completo:
1. Cajero busca producto por nombre / código
2. Tap en producto → entra al carrito
3. Selecciona método de pago
4. "COMPLETAR VENTA"
5. Ticket impreso aparece

Caption: *"Tu cajero más nuevo lo aprende en 10 minutos. Sin manuales."*

---

### 3.4 Features detalladas (grid de 6)

3 columnas × 2 filas. Cada card: ícono, título corto, descripción de 2-3 líneas, mini-screenshot.

| # | Feature | Headline | Descripción |
|---|---|---|---|
| 1 | POS multi-caja | **Cajas con nombre y dueño** | Cada cajero abre la caja que se le asignó. El dueño ve cuánto lleva vendido cada uno en vivo. |
| 2 | NCF automático | **Comprobantes fiscales sin error** | Cargas tu secuencia DGII una vez. El sistema asigna NCF automáticamente al cobrar. Alerta cuando quedan pocos. |
| 3 | Inventario en tiempo real | **Stock que no miente** | Cada venta resta del inventario. Compras lo suben. Alertas de stock mínimo. Mermas con motivo. |
| 4 | Cotizaciones | **Cotiza, aprueba, factura** | Genera cotizaciones que se convierten en venta con un click. Vencimiento automático. |
| 5 | Crédito a clientes | **Ventas a crédito con vencimiento** | Plazo configurable por venta. Alerta cuando vencen. Cobranzas en pantalla aparte. |
| 6 | Reportes y DGII | **606, 607, IT-1 sin Excel** | Exporta los formatos oficiales DGII. Cierre Z fiscal sellado e inmutable. P&L del mes en un click. |

---

### 3.5 "Cómo funciona" (3 pasos)

```
1️⃣ Te registrás → 2️⃣ Cargás productos → 3️⃣ Empezás a vender
   (1 minuto)         (importar Excel)      (mismo día)
```

Bajo cada paso, frase de 1 línea explicativa. Botón final `Empezar gratis`.

---

### 3.6 Testimonios (3 cards)

Cuando tengamos. Mientras no, placeholder con casos hipotéticos o "Próximamente, historias de comercios reales".

Estructura: foto del dueño · nombre · negocio · ciudad · 1-2 líneas de testimonio.

> *"Tenía 3 cuadernos y un Excel. Ahora tengo todo en un solo lugar y mi contadora me agradece todos los meses."*
> — **Juan Pérez**, Colmado El Vecino · La Vega

---

### 3.7 Pricing

3 planes en cards. Hacelo simple — los detalles van en `/pricing`.

| | **Inicial** | **Pro** ⭐ | **Empresa** |
|---|---|---|---|
| **Precio** | RD$ 0/mes | RD$ X/mes | A medida |
| Sucursales | 1 | Hasta 3 | Ilimitadas |
| Usuarios | 2 | 10 | Ilimitados |
| NCF auto | ✅ | ✅ | ✅ |
| Reportes DGII | ✅ | ✅ | ✅ |
| Cotizaciones | — | ✅ | ✅ |
| Caja chica | — | ✅ | ✅ |
| Soporte | Email | WhatsApp + Email | Dedicado |
| | `Empezar gratis` | `Probar Pro` | `Contactar ventas` |

Si todavía no querés precios fijos, mostrá solo "Inicial gratis" y "Contactar para Pro/Empresa".

---

### 3.8 FAQ (collapsible, 6-8 preguntas)

Las que el usuario seguro va a tener:
- ¿Necesito instalar algo? → No, es 100% web.
- ¿Funciona offline? → Aún no, pero está en roadmap.
- ¿Puedo usar mi impresora térmica actual? → Sí, cualquier impresora compatible con web printing.
- ¿Cómo cargo mis productos existentes? → Importás un Excel con la plantilla que damos.
- ¿Mis datos están seguros? → Encripción TLS, backups diarios, RLS multi-empresa.
- ¿Puedo cancelar cuando quiera? → Sí, sin penalización.
- ¿Sirve para restaurante? → Sí, soporte de mesas en roadmap.
- ¿Genera 606 y 607? → Sí, en formato TXT oficial DGII listo para subir.

---

### 3.9 CTA final

Fondo de color brand (`#0B5ED7`), texto blanco grande:

> **¿Listo para dejar el cuaderno?**
> Empezás gratis. Sin tarjeta. Sin instalación.
>
> `[ Empezar ahora ]`

---

### 3.10 Footer

```
Shop+                    Producto       Empresa        Recursos
[logo]                          POS            Sobre nosotros Documentación
"Sistema POS multi-sucursal      Reportes       Contacto       Guía DGII
 para RD"                       Cotizaciones   WhatsApp       Status

© 2026 Shop+ · Términos · Privacidad
```

---

## 4. Diseño visual

| Elemento | Valor |
|---|---|
| **Color primario** | `#0B5ED7` (brand del sistema) |
| **Color secundario** | `#22C55E` (verde — éxito, CTAs) |
| **Fondos** | Blanco + gris claro `#F8FAFC` |
| **Tipografía** | Inter (Google Fonts) — 16px base, 48px hero |
| **Border radius** | 12px (cards), 8px (botones) |
| **Sombras** | Suaves `0 4px 12px rgba(0,0,0,0.05)` |
| **Tono visual** | Limpio, moderno, profesional. No "startupero excesivo". Foto-references: Loyverse, Lightspeed, Square. |

**Imágenes:**
- Mockups del POS reales (no stock photos)
- 1 foto humana (dueño usando el POS) en el hero o testimonios
- Íconos consistentes — usar Lucide o Phosphor

---

## 5. SEO / Metadata

```html
<title>Shop+ — POS multi-sucursal con NCF automático para RD</title>
<meta name="description" content="Sistema de punto de venta dominicano con NCF, 606/607/IT-1, multi-sucursal y reportes en tiempo real. Empezás gratis.">
<meta property="og:image" content="/og-image.png"> <!-- 1200×630 -->
```

**Keywords primarias:**
- sistema POS república dominicana
- punto de venta NCF
- facturación DGII
- POS multi sucursal RD
- exportar 606 607 DGII

**Schema markup:** `SoftwareApplication` con `aggregateRating` cuando tengamos reseñas.

---

## 6. Métricas de éxito

| Métrica | Target a 3 meses |
|---|---|
| Visitas únicas / mes | 5,000 |
| Tasa de conversión visitante → signup | 4% |
| Tasa signup → primera venta | 60% |
| Tiempo promedio en página | 1:30 |
| Bounce rate | < 55% |

Tracking con **Plausible** o **Posthog** (preferí self-hosted, no Google Analytics, para alinear con el tono privacy-aware del sistema).

---

## 7. Tech stack sugerido

Como ya tenés Flutter para la app, dos opciones para la landing:

**Opción A — Recomendada: Astro + Tailwind**
- Build estático (mejor SEO y performance)
- Deploy en mismo Coolify, dominio `busiposweb.com`
- App Flutter se mueve a `app.busiposweb.com`
- Tiempo de implementación: 1-2 días

**Opción B — Flutter Web**
- Mantenés stack único
- Performance peor para landing (Flutter web no es ideal para landings públicas — el bundle es enorme, SEO limitado)
- No recomendado

---

## 8. Roadmap de implementación

| Fase | Entregable | Días |
|---|---|---|
| 1 | Wireframes en Figma | 2 |
| 2 | Copywriting (headlines, FAQ, microcopy) | 2 |
| 3 | Build estático Astro + Tailwind | 4 |
| 4 | Screenshots/GIFs del POS | 1 |
| 5 | SEO + analytics + Open Graph | 1 |
| 6 | Deploy a Coolify + DNS | 1 |
| 7 | Testing en mobile + ajustes | 2 |
| **Total** | | **~2 semanas** |

---

## 9. Decisiones abiertas

1. **¿Tenés precios fijos para Pro/Empresa o los manejamos "a contactar"?**
2. **¿Querés mostrar logos de clientes reales en una sección "Empresas que confían"?** (Si sí, mandar 4-6 logos.)
3. **¿Tenés un video del producto o lo grabamos?**
4. **Dominio definitivo: `busiposweb.com` (raíz) para landing y `app.busiposweb.com` para la app?**
5. **¿Querés blog/recursos (artículos sobre DGII, NCF) o solo landing por ahora?**
