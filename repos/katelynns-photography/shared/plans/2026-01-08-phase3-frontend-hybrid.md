# Phase 3: Frontend (Hybrid Approach) - Detailed Implementation Plan

## Overview

This plan details the frontend implementation for Katelynn's Photography website using a hybrid architecture:

- **Part A: Astro** - Public portfolio site (galleries, about, contact form)
- **Part B: HTMX + FastAPI + Jinja2** - Client portal (login, album access, photo downloads)

Building on Phases 1-2 (infrastructure and backend Lambda functions), this phase creates the user-facing components that deploy to S3/CloudFront.

## Current State Analysis

### Existing Infrastructure (from Phases 1-2)

**Phase 1 Terraform Outputs:**

- API Gateway: `https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com`
- Cognito User Pool: `us-east-2_bn71poxi6`
- Cognito Client ID: `6a5h8p858dg9laj544ijvu9gro`
- S3 Buckets:
  - `katelynns-photography-website` - Static site files
  - `katelynns-photography-portfolio-assets` - Public portfolio images
  - `katelynns-photography-client-albums` - Private client albums
- CloudFront: Pending AWS account verification

**Phase 2 Backend Endpoints:**

- `POST /contact` - Contact form submission (unauthenticated)
- `GET /api/albums` - List client's albums (Cognito authenticated)
- `GET /api/albums/{album_id}` - Get album details (authenticated)
- `GET /api/albums/{album_id}/files` - List files with download URLs (authenticated)
- `GET /api/albums/{album_id}/download` - Get presigned download URL (authenticated)
- `POST /admin/albums` - Create album (admin only)

### Current Frontend Status

**NO FRONTEND EXISTS** - The project has backend and infrastructure only:

- No `package.json` or Node.js configuration
- No Astro, React, or any frontend framework
- No HTML templates or static assets
- No CSS/JavaScript files

## Desired End State

After completing this phase:

### Part A: Astro Public Site

1. **Landing Page** - Hero image, featured galleries, call-to-action
2. **Portfolio Page** - Gallery showcase with categories (Wedding, Portrait, Event)
3. **About Page** - Bio, experience, equipment info
4. **Contact Page** - Form that submits to Lambda backend
5. **Image Optimization** - Automatic WebP/AVIF conversion, responsive srcsets

### Part B: HTMX Client Portal

1. **Login Page** - Cognito authentication via HTMX
2. **Dashboard** - Client's available albums
3. **Album View** - Photo thumbnails with individual download links
4. **Bulk Download** - Download all photos in album

### Verification

- Public site loads via CloudFront URL
- All pages render correctly on mobile and desktop
- Contact form submits successfully and sends email
- Client can login with Cognito credentials
- Authenticated client sees their albums
- Presigned URLs allow photo downloads
- Page load time < 3 seconds on 3G connection

## What We're NOT Doing

- Payment processing (future enhancement)
- Image upload through web interface (admin uses AWS Console/CLI)
- Real-time notifications
- Social media integration
- SEO optimization beyond basic meta tags (Phase 5)
- Email marketing integration

---

## Implementation Approach

### Directory Structure

```
katelynns-photography/
├── astro-portfolio/              # NEW: Astro public site
│   ├── src/
│   │   ├── pages/
│   │   │   ├── index.astro      # Landing page
│   │   │   ├── portfolio.astro  # Gallery showcase
│   │   │   ├── about.astro      # Bio/info page
│   │   │   └── contact.astro    # Contact form
│   │   ├── components/
│   │   │   ├── Gallery.astro    # Masonry photo grid
│   │   │   ├── Lightbox.astro   # Full-screen image viewer
│   │   │   ├── ContactForm.astro# Form component
│   │   │   ├── Navigation.astro # Header/nav
│   │   │   └── Footer.astro     # Footer
│   │   ├── layouts/
│   │   │   └── Layout.astro     # Base HTML template
│   │   └── styles/
│   │       └── global.css       # Global styles
│   ├── public/                   # Static assets (favicon, etc.)
│   ├── astro.config.mjs         # Astro configuration
│   ├── tailwind.config.mjs      # Tailwind CSS config
│   └── package.json
│
├── backend/                      # Existing Lambda functions
│   ├── client_portal/           # FastAPI app - MODIFY for HTMX
│   │   ├── app/
│   │   │   ├── main.py          # Add Jinja2 templates
│   │   │   ├── templates/       # NEW: HTML templates
│   │   │   │   ├── base.html
│   │   │   │   ├── login.html
│   │   │   │   ├── albums.html
│   │   │   │   └── album_detail.html
│   │   │   └── static/          # NEW: CSS/JS for portal
│   │   │       └── portal.css
│   │   └── requirements.txt     # Add jinja2
│   └── ...
│
├── terraform/                    # Existing infrastructure
├── scripts/
│   ├── deploy_lambda.sh         # Existing
│   └── deploy_astro.sh          # NEW: Deploy Astro to S3
└── thoughts/
```

---

## Part A: Astro Public Portfolio Site

---

## Phase 3.1: Astro Project Setup

### Overview

Initialize Astro project with Tailwind CSS for the public portfolio site.

### Changes Required:

#### 1. Create Astro project

```bash
cd ~/repos/katelynns-photography
npm create astro@latest astro-portfolio -- --template minimal --no-git
cd astro-portfolio
npm install
```

#### 2. Install dependencies

```bash
npm install @astrojs/tailwind tailwindcss
npm install @astrojs/sitemap
```

#### 3. Configure astro.config.mjs

**File**: `astro-portfolio/astro.config.mjs`

```javascript
import { defineConfig } from "astro/config";
import tailwind from "@astrojs/tailwind";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://katelynnsphotography.com", // Update when domain ready
  integrations: [tailwind(), sitemap()],
  output: "static",
  build: {
    assets: "_assets",
  },
  image: {
    // Use Sharp for image optimization
    service: {
      entrypoint: "astro/assets/services/sharp",
    },
  },
});
```

#### 4. Configure Tailwind

**File**: `astro-portfolio/tailwind.config.mjs`

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: ["./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}"],
  theme: {
    extend: {
      colors: {
        // Photography site color palette
        primary: {
          50: "#fdf8f6",
          100: "#f2e8e5",
          200: "#eaddd7",
          300: "#e0cec7",
          400: "#d2bab0",
          500: "#bfa094",
          600: "#a18072",
          700: "#977669",
          800: "#846358",
          900: "#43302b",
        },
        accent: {
          DEFAULT: "#d4a574",
          dark: "#b8956a",
        },
      },
      fontFamily: {
        serif: ["Playfair Display", "Georgia", "serif"],
        sans: ["Lato", "Helvetica", "Arial", "sans-serif"],
      },
    },
  },
  plugins: [],
};
```

#### 5. Create global styles

**File**: `astro-portfolio/src/styles/global.css`

```css
@import url("https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;500;600;700&family=Lato:wght@300;400;700&display=swap");

@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  html {
    scroll-behavior: smooth;
  }

  body {
    @apply font-sans text-gray-800 bg-primary-50;
  }

  h1,
  h2,
  h3,
  h4,
  h5,
  h6 {
    @apply font-serif;
  }
}

@layer components {
  .btn-primary {
    @apply inline-block px-6 py-3 bg-accent text-white font-medium rounded-sm
           hover:bg-accent-dark transition-colors duration-200;
  }

  .btn-secondary {
    @apply inline-block px-6 py-3 border-2 border-primary-800 text-primary-800
           font-medium rounded-sm hover:bg-primary-800 hover:text-white
           transition-colors duration-200;
  }

  .section-heading {
    @apply text-3xl md:text-4xl font-serif text-primary-900 mb-4;
  }
}

/* Lightbox styles */
.lightbox-overlay {
  @apply fixed inset-0 bg-black/90 z-50 flex items-center justify-center;
}

.lightbox-image {
  @apply max-h-[90vh] max-w-[90vw] object-contain;
}
```

### Success Criteria:

#### Automated Verification:

- [x] `cd astro-portfolio && npm install` succeeds
- [x] `npm run build` completes without errors
- [ ] `npm run dev` starts development server

#### Manual Verification:

- [ ] Development server accessible at http://localhost:4321
- [ ] Tailwind styles applied correctly

---

## Phase 3.2: Base Layout and Navigation

### Overview

Create the base HTML layout and navigation components shared across all pages.

### Changes Required:

#### 1. Create base layout

**File**: `astro-portfolio/src/layouts/Layout.astro`

```astro
---
import '../styles/global.css';
import Navigation from '../components/Navigation.astro';
import Footer from '../components/Footer.astro';

interface Props {
  title: string;
  description?: string;
  image?: string;
}

const {
  title,
  description = "Katelynn's Photography - Capturing life's beautiful moments",
  image = "/og-image.jpg"
} = Astro.props;

const canonicalURL = new URL(Astro.url.pathname, Astro.site);
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content={description} />

    <!-- Open Graph / Social -->
    <meta property="og:type" content="website" />
    <meta property="og:url" content={canonicalURL} />
    <meta property="og:title" content={title} />
    <meta property="og:description" content={description} />
    <meta property="og:image" content={new URL(image, Astro.site)} />

    <link rel="canonical" href={canonicalURL} />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />

    <title>{title} | Katelynn's Photography</title>
  </head>
  <body class="min-h-screen flex flex-col">
    <Navigation />

    <main class="flex-grow">
      <slot />
    </main>

    <Footer />
  </body>
</html>
```

#### 2. Create Navigation component

**File**: `astro-portfolio/src/components/Navigation.astro`

```astro
---
const currentPath = Astro.url.pathname;

const navLinks = [
  { href: '/', label: 'Home' },
  { href: '/portfolio', label: 'Portfolio' },
  { href: '/about', label: 'About' },
  { href: '/contact', label: 'Contact' },
];

const isActive = (href: string) => {
  if (href === '/') return currentPath === '/';
  return currentPath.startsWith(href);
};
---

<header class="bg-white/80 backdrop-blur-md sticky top-0 z-40 border-b border-primary-200">
  <nav class="container mx-auto px-4 py-4">
    <div class="flex items-center justify-between">
      <!-- Logo -->
      <a href="/" class="text-2xl font-serif text-primary-900 hover:text-accent transition-colors">
        Katelynn's Photography
      </a>

      <!-- Desktop Navigation -->
      <ul class="hidden md:flex items-center space-x-8">
        {navLinks.map((link) => (
          <li>
            <a
              href={link.href}
              class:list={[
                'text-sm uppercase tracking-wider transition-colors duration-200',
                isActive(link.href)
                  ? 'text-accent font-medium'
                  : 'text-primary-700 hover:text-accent'
              ]}
            >
              {link.label}
            </a>
          </li>
        ))}
        <li>
          <a
            href="/client"
            class="text-sm uppercase tracking-wider text-primary-600 hover:text-accent transition-colors"
          >
            Client Login
          </a>
        </li>
      </ul>

      <!-- Mobile Menu Button -->
      <button
        id="mobile-menu-btn"
        class="md:hidden p-2 text-primary-700"
        aria-label="Toggle menu"
      >
        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>
    </div>

    <!-- Mobile Navigation -->
    <div id="mobile-menu" class="hidden md:hidden mt-4 pb-4">
      <ul class="flex flex-col space-y-4">
        {navLinks.map((link) => (
          <li>
            <a
              href={link.href}
              class:list={[
                'block text-sm uppercase tracking-wider transition-colors',
                isActive(link.href)
                  ? 'text-accent font-medium'
                  : 'text-primary-700'
              ]}
            >
              {link.label}
            </a>
          </li>
        ))}
        <li class="pt-4 border-t border-primary-200">
          <a href="/client" class="text-sm uppercase tracking-wider text-primary-600">
            Client Login
          </a>
        </li>
      </ul>
    </div>
  </nav>
</header>

<script>
  const menuBtn = document.getElementById('mobile-menu-btn');
  const mobileMenu = document.getElementById('mobile-menu');

  menuBtn?.addEventListener('click', () => {
    mobileMenu?.classList.toggle('hidden');
  });
</script>
```

#### 3. Create Footer component

**File**: `astro-portfolio/src/components/Footer.astro`

```astro
---
const currentYear = new Date().getFullYear();
---

<footer class="bg-primary-900 text-primary-200 py-12">
  <div class="container mx-auto px-4">
    <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
      <!-- Brand -->
      <div>
        <h3 class="font-serif text-xl text-white mb-4">Katelynn's Photography</h3>
        <p class="text-sm leading-relaxed">
          Capturing life's beautiful moments with artistry and heart.
          Specializing in weddings, portraits, and special events.
        </p>
      </div>

      <!-- Quick Links -->
      <div>
        <h4 class="font-medium text-white mb-4">Quick Links</h4>
        <ul class="space-y-2 text-sm">
          <li><a href="/portfolio" class="hover:text-accent transition-colors">Portfolio</a></li>
          <li><a href="/about" class="hover:text-accent transition-colors">About</a></li>
          <li><a href="/contact" class="hover:text-accent transition-colors">Contact</a></li>
          <li><a href="/client" class="hover:text-accent transition-colors">Client Portal</a></li>
        </ul>
      </div>

      <!-- Contact Info -->
      <div>
        <h4 class="font-medium text-white mb-4">Get in Touch</h4>
        <ul class="space-y-2 text-sm">
          <li>
            <a href="mailto:hello@katelynnsphotography.com" class="hover:text-accent transition-colors">
              hello@katelynnsphotography.com
            </a>
          </li>
          <li>Based in [Your Location]</li>
        </ul>
      </div>
    </div>

    <div class="border-t border-primary-700 mt-8 pt-8 text-center text-sm">
      <p>&copy; {currentYear} Katelynn's Photography. All rights reserved.</p>
    </div>
  </div>
</footer>
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] No TypeScript/Astro errors in components

#### Manual Verification:

- [ ] Navigation displays correctly on desktop and mobile
- [ ] Mobile menu toggles properly
- [ ] Footer displays with correct year

---

## Phase 3.3: Landing Page (Home)

### Overview

Create the homepage with hero section, featured galleries, and call-to-action.

### Changes Required:

#### 1. Create homepage

**File**: `astro-portfolio/src/pages/index.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import { Image } from 'astro:assets';

// Featured gallery categories
const categories = [
  {
    title: 'Weddings',
    description: 'Capturing your special day with elegance and emotion',
    image: '/images/wedding-featured.jpg',
    href: '/portfolio?category=wedding',
  },
  {
    title: 'Portraits',
    description: 'Beautiful portraits that tell your story',
    image: '/images/portrait-featured.jpg',
    href: '/portfolio?category=portrait',
  },
  {
    title: 'Events',
    description: 'Preserving memories from life\'s celebrations',
    image: '/images/event-featured.jpg',
    href: '/portfolio?category=event',
  },
];
---

<Layout title="Home" description="Professional photography capturing life's beautiful moments. Specializing in weddings, portraits, and events.">
  <!-- Hero Section -->
  <section class="relative h-screen flex items-center justify-center">
    <!-- Background Image -->
    <div class="absolute inset-0 z-0">
      <img
        src="/images/hero-bg.jpg"
        alt=""
        class="w-full h-full object-cover"
        loading="eager"
      />
      <div class="absolute inset-0 bg-black/40"></div>
    </div>

    <!-- Hero Content -->
    <div class="relative z-10 text-center text-white px-4 max-w-4xl">
      <h1 class="text-4xl md:text-6xl lg:text-7xl font-serif mb-6">
        Capturing Life's<br />Beautiful Moments
      </h1>
      <p class="text-lg md:text-xl text-white/90 mb-8 max-w-2xl mx-auto">
        Professional photography with heart and artistry.
        Let's create something beautiful together.
      </p>
      <div class="flex flex-col sm:flex-row gap-4 justify-center">
        <a href="/portfolio" class="btn-primary">
          View Portfolio
        </a>
        <a href="/contact" class="btn-secondary border-white text-white hover:bg-white hover:text-primary-900">
          Get in Touch
        </a>
      </div>
    </div>

    <!-- Scroll Indicator -->
    <div class="absolute bottom-8 left-1/2 -translate-x-1/2 animate-bounce">
      <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
      </svg>
    </div>
  </section>

  <!-- Featured Work Section -->
  <section class="py-20 bg-white">
    <div class="container mx-auto px-4">
      <div class="text-center mb-12">
        <h2 class="section-heading">Featured Work</h2>
        <p class="text-primary-600 max-w-2xl mx-auto">
          Explore a curated selection of my favorite captures across different styles and occasions.
        </p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
        {categories.map((category) => (
          <a
            href={category.href}
            class="group relative overflow-hidden rounded-sm aspect-[3/4]"
          >
            <img
              src={category.image}
              alt={category.title}
              class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
              loading="lazy"
            />
            <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent"></div>
            <div class="absolute bottom-0 left-0 right-0 p-6 text-white">
              <h3 class="text-2xl font-serif mb-2">{category.title}</h3>
              <p class="text-white/80 text-sm">{category.description}</p>
            </div>
          </a>
        ))}
      </div>

      <div class="text-center mt-12">
        <a href="/portfolio" class="btn-secondary">
          View All Work
        </a>
      </div>
    </div>
  </section>

  <!-- About Teaser Section -->
  <section class="py-20 bg-primary-100">
    <div class="container mx-auto px-4">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
        <div class="order-2 lg:order-1">
          <h2 class="section-heading">Hello, I'm Katelynn</h2>
          <p class="text-primary-700 mb-6 leading-relaxed">
            With a passion for storytelling and an eye for the extraordinary in everyday moments,
            I've been capturing life's beautiful chapters for over [X] years.
            My approach combines artistic vision with genuine connection,
            creating images that feel both timeless and authentically you.
          </p>
          <a href="/about" class="btn-primary">
            Learn More About Me
          </a>
        </div>
        <div class="order-1 lg:order-2">
          <img
            src="/images/about-teaser.jpg"
            alt="Katelynn, photographer"
            class="w-full rounded-sm shadow-lg"
            loading="lazy"
          />
        </div>
      </div>
    </div>
  </section>

  <!-- CTA Section -->
  <section class="py-20 bg-primary-900 text-white text-center">
    <div class="container mx-auto px-4 max-w-3xl">
      <h2 class="text-3xl md:text-4xl font-serif mb-6">
        Ready to Create Something Beautiful?
      </h2>
      <p class="text-primary-200 mb-8">
        Whether it's your wedding day, a family portrait, or a special event,
        I'd love to hear about your vision and help bring it to life.
      </p>
      <a href="/contact" class="btn-primary bg-accent hover:bg-accent-dark">
        Start a Conversation
      </a>
    </div>
  </section>
</Layout>
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] No missing imports or undefined variables

#### Manual Verification:

- [ ] Hero section displays with background image (placeholder initially)
- [ ] Featured work grid displays three categories
- [ ] All links navigate correctly
- [ ] Responsive design works on mobile

---

## Phase 3.4: Portfolio Gallery Page

### Overview

Create the portfolio page with filterable gallery and lightbox viewer.

### Changes Required:

#### 1. Create Gallery component

**File**: `astro-portfolio/src/components/Gallery.astro`

```astro
---
interface GalleryImage {
  src: string;
  alt: string;
  category: string;
  width?: number;
  height?: number;
}

interface Props {
  images: GalleryImage[];
  showFilter?: boolean;
}

const { images, showFilter = true } = Astro.props;

// Get unique categories
const categories = ['all', ...new Set(images.map(img => img.category))];
---

<div class="gallery-container">
  {showFilter && (
    <div class="flex flex-wrap justify-center gap-4 mb-8">
      {categories.map((cat) => (
        <button
          class="filter-btn px-4 py-2 text-sm uppercase tracking-wider border border-primary-300
                 rounded-sm transition-colors data-[active=true]:bg-primary-800
                 data-[active=true]:text-white data-[active=true]:border-primary-800
                 hover:border-primary-800"
          data-category={cat}
          data-active={cat === 'all'}
        >
          {cat}
        </button>
      ))}
    </div>
  )}

  <div class="gallery-grid grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
    {images.map((image, index) => (
      <div
        class="gallery-item relative overflow-hidden aspect-square cursor-pointer group"
        data-category={image.category}
      >
        <img
          src={image.src}
          alt={image.alt}
          class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
          loading="lazy"
          data-lightbox-src={image.src}
          data-lightbox-index={index}
        />
        <div class="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors duration-300 flex items-center justify-center">
          <span class="text-white opacity-0 group-hover:opacity-100 transition-opacity">
            <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7" />
            </svg>
          </span>
        </div>
      </div>
    ))}
  </div>
</div>

<!-- Lightbox -->
<div id="lightbox" class="lightbox-overlay hidden" aria-hidden="true">
  <button
    id="lightbox-close"
    class="absolute top-4 right-4 text-white hover:text-accent z-50"
    aria-label="Close lightbox"
  >
    <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
    </svg>
  </button>

  <button
    id="lightbox-prev"
    class="absolute left-4 top-1/2 -translate-y-1/2 text-white hover:text-accent z-50"
    aria-label="Previous image"
  >
    <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
    </svg>
  </button>

  <button
    id="lightbox-next"
    class="absolute right-4 top-1/2 -translate-y-1/2 text-white hover:text-accent z-50"
    aria-label="Next image"
  >
    <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
    </svg>
  </button>

  <img id="lightbox-image" src="" alt="" class="lightbox-image" />
</div>

<script>
  // Gallery filtering
  const filterBtns = document.querySelectorAll('.filter-btn');
  const galleryItems = document.querySelectorAll('.gallery-item');

  filterBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const category = btn.dataset.category;

      // Update active state
      filterBtns.forEach(b => b.dataset.active = 'false');
      btn.dataset.active = 'true';

      // Filter items
      galleryItems.forEach(item => {
        if (category === 'all' || item.dataset.category === category) {
          item.style.display = '';
        } else {
          item.style.display = 'none';
        }
      });
    });
  });

  // Lightbox functionality
  const lightbox = document.getElementById('lightbox');
  const lightboxImage = document.getElementById('lightbox-image') as HTMLImageElement;
  const lightboxClose = document.getElementById('lightbox-close');
  const lightboxPrev = document.getElementById('lightbox-prev');
  const lightboxNext = document.getElementById('lightbox-next');

  let currentIndex = 0;
  let visibleImages: HTMLImageElement[] = [];

  function updateVisibleImages() {
    visibleImages = Array.from(document.querySelectorAll('.gallery-item:not([style*="display: none"]) img'));
  }

  function openLightbox(index: number) {
    updateVisibleImages();
    currentIndex = index;
    if (lightboxImage && visibleImages[currentIndex]) {
      lightboxImage.src = visibleImages[currentIndex].dataset.lightboxSrc || '';
      lightboxImage.alt = visibleImages[currentIndex].alt;
    }
    lightbox?.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    lightbox?.classList.add('hidden');
    document.body.style.overflow = '';
  }

  function showPrev() {
    currentIndex = (currentIndex - 1 + visibleImages.length) % visibleImages.length;
    if (lightboxImage) {
      lightboxImage.src = visibleImages[currentIndex].dataset.lightboxSrc || '';
      lightboxImage.alt = visibleImages[currentIndex].alt;
    }
  }

  function showNext() {
    currentIndex = (currentIndex + 1) % visibleImages.length;
    if (lightboxImage) {
      lightboxImage.src = visibleImages[currentIndex].dataset.lightboxSrc || '';
      lightboxImage.alt = visibleImages[currentIndex].alt;
    }
  }

  // Event listeners
  galleryItems.forEach((item, i) => {
    item.addEventListener('click', () => openLightbox(i));
  });

  lightboxClose?.addEventListener('click', closeLightbox);
  lightboxPrev?.addEventListener('click', showPrev);
  lightboxNext?.addEventListener('click', showNext);

  lightbox?.addEventListener('click', (e) => {
    if (e.target === lightbox) closeLightbox();
  });

  document.addEventListener('keydown', (e) => {
    if (lightbox?.classList.contains('hidden')) return;
    if (e.key === 'Escape') closeLightbox();
    if (e.key === 'ArrowLeft') showPrev();
    if (e.key === 'ArrowRight') showNext();
  });
</script>
```

#### 2. Create Portfolio page

**File**: `astro-portfolio/src/pages/portfolio.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import Gallery from '../components/Gallery.astro';

// Sample gallery images - replace with actual CloudFront URLs
const galleryImages = [
  { src: '/images/gallery/wedding-1.jpg', alt: 'Wedding ceremony', category: 'wedding' },
  { src: '/images/gallery/wedding-2.jpg', alt: 'Bride portrait', category: 'wedding' },
  { src: '/images/gallery/wedding-3.jpg', alt: 'Reception details', category: 'wedding' },
  { src: '/images/gallery/portrait-1.jpg', alt: 'Family portrait', category: 'portrait' },
  { src: '/images/gallery/portrait-2.jpg', alt: 'Senior portrait', category: 'portrait' },
  { src: '/images/gallery/portrait-3.jpg', alt: 'Couple session', category: 'portrait' },
  { src: '/images/gallery/event-1.jpg', alt: 'Birthday celebration', category: 'event' },
  { src: '/images/gallery/event-2.jpg', alt: 'Corporate event', category: 'event' },
  { src: '/images/gallery/event-3.jpg', alt: 'Anniversary party', category: 'event' },
];
---

<Layout title="Portfolio" description="Browse my photography portfolio featuring weddings, portraits, and special events.">
  <!-- Page Header -->
  <section class="pt-32 pb-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h1 class="text-4xl md:text-5xl font-serif text-primary-900 mb-4">Portfolio</h1>
      <p class="text-primary-600 max-w-2xl mx-auto">
        A collection of cherished moments and beautiful stories captured through my lens.
      </p>
    </div>
  </section>

  <!-- Gallery Section -->
  <section class="py-16">
    <div class="container mx-auto px-4">
      <Gallery images={galleryImages} showFilter={true} />
    </div>
  </section>

  <!-- CTA Section -->
  <section class="py-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h2 class="text-2xl md:text-3xl font-serif text-primary-900 mb-4">
        Like What You See?
      </h2>
      <p class="text-primary-600 mb-8 max-w-xl mx-auto">
        Let's discuss how we can create beautiful images for your special occasion.
      </p>
      <a href="/contact" class="btn-primary">
        Get in Touch
      </a>
    </div>
  </section>
</Layout>
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] Gallery component renders without errors

#### Manual Verification:

- [ ] Filter buttons filter images correctly
- [ ] Lightbox opens on image click
- [ ] Keyboard navigation works (Escape, Arrow keys)
- [ ] Responsive grid layout works

---

## Phase 3.5: About and Contact Pages

### Overview

Create the About page and Contact page with form that submits to the Lambda backend.

### Changes Required:

#### 1. Create About page

**File**: `astro-portfolio/src/pages/about.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
---

<Layout title="About" description="Learn more about Katelynn, a professional photographer specializing in weddings, portraits, and events.">
  <!-- Page Header -->
  <section class="pt-32 pb-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h1 class="text-4xl md:text-5xl font-serif text-primary-900 mb-4">About Me</h1>
    </div>
  </section>

  <!-- Main Content -->
  <section class="py-16">
    <div class="container mx-auto px-4">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-12 items-start max-w-6xl mx-auto">
        <!-- Image -->
        <div>
          <img
            src="/images/about-full.jpg"
            alt="Katelynn with camera"
            class="w-full rounded-sm shadow-lg"
          />
        </div>

        <!-- Content -->
        <div class="space-y-6">
          <h2 class="text-3xl font-serif text-primary-900">Hello, I'm Katelynn</h2>

          <p class="text-primary-700 leading-relaxed">
            Photography has been my passion for as long as I can remember. What started as
            a childhood fascination with my father's old film camera has blossomed into a
            fulfilling career capturing life's most precious moments.
          </p>

          <p class="text-primary-700 leading-relaxed">
            I believe every photograph should tell a story. My approach combines technical
            expertise with genuine connection, creating images that feel both artistic and
            authentically you. Whether it's the joyful tears at a wedding ceremony, the
            quiet intimacy of a family portrait, or the energy of a celebration, I strive
            to capture the emotion and beauty of each moment.
          </p>

          <h3 class="text-xl font-serif text-primary-900 pt-4">My Approach</h3>

          <ul class="space-y-3 text-primary-700">
            <li class="flex items-start">
              <span class="text-accent mr-3">&#10003;</span>
              <span><strong>Natural & Candid:</strong> I capture real moments, not forced poses</span>
            </li>
            <li class="flex items-start">
              <span class="text-accent mr-3">&#10003;</span>
              <span><strong>Detail-Oriented:</strong> Every small moment matters</span>
            </li>
            <li class="flex items-start">
              <span class="text-accent mr-3">&#10003;</span>
              <span><strong>Relaxed Sessions:</strong> I create a comfortable, fun atmosphere</span>
            </li>
            <li class="flex items-start">
              <span class="text-accent mr-3">&#10003;</span>
              <span><strong>Quick Turnaround:</strong> Your photos delivered within 2-3 weeks</span>
            </li>
          </ul>

          <div class="pt-6">
            <a href="/contact" class="btn-primary">
              Let's Work Together
            </a>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- Equipment Section (Optional) -->
  <section class="py-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center max-w-4xl">
      <h2 class="text-2xl font-serif text-primary-900 mb-8">Professional Equipment</h2>
      <p class="text-primary-600">
        I use professional-grade cameras and lenses to ensure the highest quality images.
        My kit includes backup equipment for every shoot, so you never have to worry about
        technical issues on your special day.
      </p>
    </div>
  </section>
</Layout>
```

#### 2. Create ContactForm component

**File**: `astro-portfolio/src/components/ContactForm.astro`

```astro
---
interface Props {
  apiUrl: string;
}

const { apiUrl } = Astro.props;
---

<form id="contact-form" class="space-y-6" data-api-url={apiUrl}>
  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
    <!-- Name -->
    <div>
      <label for="name" class="block text-sm font-medium text-primary-700 mb-2">
        Name <span class="text-red-500">*</span>
      </label>
      <input
        type="text"
        id="name"
        name="name"
        required
        minlength="2"
        class="w-full px-4 py-3 border border-primary-300 rounded-sm focus:ring-2
               focus:ring-accent focus:border-accent outline-none transition-colors"
        placeholder="Your name"
      />
    </div>

    <!-- Email -->
    <div>
      <label for="email" class="block text-sm font-medium text-primary-700 mb-2">
        Email <span class="text-red-500">*</span>
      </label>
      <input
        type="email"
        id="email"
        name="email"
        required
        class="w-full px-4 py-3 border border-primary-300 rounded-sm focus:ring-2
               focus:ring-accent focus:border-accent outline-none transition-colors"
        placeholder="your@email.com"
      />
    </div>
  </div>

  <!-- Phone (optional) -->
  <div>
    <label for="phone" class="block text-sm font-medium text-primary-700 mb-2">
      Phone <span class="text-primary-400">(optional)</span>
    </label>
    <input
      type="tel"
      id="phone"
      name="phone"
      class="w-full px-4 py-3 border border-primary-300 rounded-sm focus:ring-2
             focus:ring-accent focus:border-accent outline-none transition-colors"
      placeholder="(555) 123-4567"
    />
  </div>

  <!-- Inquiry Type -->
  <div>
    <label for="inquiry_type" class="block text-sm font-medium text-primary-700 mb-2">
      What are you interested in? <span class="text-red-500">*</span>
    </label>
    <select
      id="inquiry_type"
      name="inquiry_type"
      required
      class="w-full px-4 py-3 border border-primary-300 rounded-sm focus:ring-2
             focus:ring-accent focus:border-accent outline-none transition-colors bg-white"
    >
      <option value="">Select an option...</option>
      <option value="wedding">Wedding Photography</option>
      <option value="portrait">Portrait Session</option>
      <option value="event">Event Photography</option>
      <option value="other">Other Inquiry</option>
    </select>
  </div>

  <!-- Message -->
  <div>
    <label for="message" class="block text-sm font-medium text-primary-700 mb-2">
      Message <span class="text-red-500">*</span>
    </label>
    <textarea
      id="message"
      name="message"
      required
      minlength="10"
      rows="5"
      class="w-full px-4 py-3 border border-primary-300 rounded-sm focus:ring-2
             focus:ring-accent focus:border-accent outline-none transition-colors resize-y"
      placeholder="Tell me about your event, preferred dates, and any questions you have..."
    ></textarea>
  </div>

  <!-- Submit Button -->
  <div>
    <button
      type="submit"
      class="btn-primary w-full md:w-auto disabled:opacity-50 disabled:cursor-not-allowed"
    >
      <span class="submit-text">Send Message</span>
      <span class="loading-text hidden">Sending...</span>
    </button>
  </div>

  <!-- Status Messages -->
  <div id="form-status" class="hidden">
    <div class="success-message hidden p-4 bg-green-100 text-green-800 rounded-sm">
      Thank you for your message! I'll get back to you within 24-48 hours.
    </div>
    <div class="error-message hidden p-4 bg-red-100 text-red-800 rounded-sm">
      Something went wrong. Please try again or email me directly.
    </div>
  </div>
</form>

<script>
  const form = document.getElementById('contact-form') as HTMLFormElement;
  const submitBtn = form?.querySelector('button[type="submit"]');
  const submitText = form?.querySelector('.submit-text');
  const loadingText = form?.querySelector('.loading-text');
  const statusDiv = document.getElementById('form-status');
  const successMsg = statusDiv?.querySelector('.success-message');
  const errorMsg = statusDiv?.querySelector('.error-message');

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();

    // Get API URL from data attribute
    const apiUrl = form.dataset.apiUrl;

    // Disable button, show loading
    if (submitBtn) submitBtn.setAttribute('disabled', 'true');
    submitText?.classList.add('hidden');
    loadingText?.classList.remove('hidden');

    // Hide previous status
    statusDiv?.classList.add('hidden');
    successMsg?.classList.add('hidden');
    errorMsg?.classList.add('hidden');

    // Gather form data
    const formData = new FormData(form);
    const data = Object.fromEntries(formData.entries());

    try {
      const response = await fetch(`${apiUrl}/contact`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(data),
      });

      const result = await response.json();

      if (response.ok && result.success) {
        // Show success
        statusDiv?.classList.remove('hidden');
        successMsg?.classList.remove('hidden');
        form.reset();
      } else {
        // Show error
        statusDiv?.classList.remove('hidden');
        errorMsg?.classList.remove('hidden');
        if (result.errors) {
          errorMsg!.textContent = result.errors.join('. ');
        }
      }
    } catch (err) {
      // Network error
      statusDiv?.classList.remove('hidden');
      errorMsg?.classList.remove('hidden');
    } finally {
      // Re-enable button
      if (submitBtn) submitBtn.removeAttribute('disabled');
      submitText?.classList.remove('hidden');
      loadingText?.classList.add('hidden');
    }
  });
</script>
```

#### 3. Create Contact page

**File**: `astro-portfolio/src/pages/contact.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import ContactForm from '../components/ContactForm.astro';

// API Gateway URL - update with actual endpoint
const apiUrl = 'https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com';
---

<Layout title="Contact" description="Get in touch to discuss your photography needs. I'd love to hear about your upcoming wedding, portrait session, or event.">
  <!-- Page Header -->
  <section class="pt-32 pb-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h1 class="text-4xl md:text-5xl font-serif text-primary-900 mb-4">Get in Touch</h1>
      <p class="text-primary-600 max-w-2xl mx-auto">
        I'd love to hear about your upcoming occasion. Fill out the form below
        and I'll get back to you within 24-48 hours.
      </p>
    </div>
  </section>

  <!-- Contact Section -->
  <section class="py-16">
    <div class="container mx-auto px-4">
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-12 max-w-6xl mx-auto">
        <!-- Contact Form -->
        <div class="lg:col-span-2">
          <ContactForm apiUrl={apiUrl} />
        </div>

        <!-- Contact Info Sidebar -->
        <div class="space-y-8">
          <div>
            <h3 class="font-serif text-xl text-primary-900 mb-4">Other Ways to Reach Me</h3>
            <ul class="space-y-4 text-primary-700">
              <li class="flex items-start">
                <svg class="w-5 h-5 text-accent mr-3 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
                <a href="mailto:hello@katelynnsphotography.com" class="hover:text-accent transition-colors">
                  hello@katelynnsphotography.com
                </a>
              </li>
              <li class="flex items-start">
                <svg class="w-5 h-5 text-accent mr-3 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
                <span>Based in [Your Location]</span>
              </li>
            </ul>
          </div>

          <div>
            <h3 class="font-serif text-xl text-primary-900 mb-4">Response Time</h3>
            <p class="text-primary-700 text-sm">
              I typically respond to inquiries within 24-48 hours during business days.
              For urgent matters, please mention it in your message.
            </p>
          </div>

          <div>
            <h3 class="font-serif text-xl text-primary-900 mb-4">Booking Info</h3>
            <p class="text-primary-700 text-sm">
              I book weddings and events 6-12 months in advance. Portrait sessions
              can often be scheduled within 2-4 weeks. Early booking is recommended
              for peak seasons (May-October).
            </p>
          </div>
        </div>
      </div>
    </div>
  </section>
</Layout>
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] Contact form component has no TypeScript errors

#### Manual Verification:

- [ ] About page displays correctly with all sections
- [ ] Contact form validates required fields
- [ ] Form submission sends data to API Gateway
- [ ] Success/error messages display appropriately
- [ ] Loading state works during submission

**Implementation Note**: After completing this phase, test the contact form end-to-end with the deployed Lambda function.

---

## Phase 3.6: Astro Deployment Setup

### Overview

Create deployment script and configure for S3/CloudFront deployment.

### Changes Required:

#### 1. Create deployment script

**File**: `scripts/deploy_astro.sh`

```bash
#!/bin/bash
# Deploy Astro site to S3 and invalidate CloudFront cache
# Usage: ./scripts/deploy_astro.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASTRO_DIR="$PROJECT_ROOT/astro-portfolio"

AWS_PROFILE="${AWS_PROFILE:-jw-dev}"
AWS_REGION="${AWS_REGION:-us-east-2}"
S3_BUCKET="katelynns-photography-website"

# Get CloudFront distribution ID from Terraform
CLOUDFRONT_ID=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")

echo "=========================================="
echo "Deploying Astro Site"
echo "=========================================="
echo "AWS Profile: $AWS_PROFILE"
echo "S3 Bucket: $S3_BUCKET"
echo "CloudFront ID: ${CLOUDFRONT_ID:-'Not configured'}"
echo ""

# Build Astro site
echo "Building Astro site..."
cd "$ASTRO_DIR"
npm run build

# Sync to S3
echo ""
echo "Syncing to S3..."
aws s3 sync dist/ "s3://$S3_BUCKET/" \
    --delete \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --cache-control "public, max-age=31536000, immutable" \
    --exclude "*.html" \
    --exclude "*.xml" \
    --exclude "*.json"

# Upload HTML files with shorter cache
aws s3 sync dist/ "s3://$S3_BUCKET/" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --cache-control "public, max-age=0, must-revalidate" \
    --exclude "*" \
    --include "*.html" \
    --include "*.xml" \
    --include "*.json"

echo "S3 sync complete!"

# Invalidate CloudFront cache if distribution exists
if [ -n "$CLOUDFRONT_ID" ]; then
    echo ""
    echo "Invalidating CloudFront cache..."
    aws cloudfront create-invalidation \
        --distribution-id "$CLOUDFRONT_ID" \
        --paths "/*" \
        --profile "$AWS_PROFILE" \
        --query 'Invalidation.Id' \
        --output text
    echo "CloudFront invalidation created!"
fi

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo "Site URL: https://$S3_BUCKET.s3.$AWS_REGION.amazonaws.com/index.html"
if [ -n "$CLOUDFRONT_ID" ]; then
    echo "CloudFront URL: Check terraform output for domain"
fi
```

#### 2. Make executable

```bash
chmod +x scripts/deploy_astro.sh
```

#### 3. Add .gitignore entries

**File**: `astro-portfolio/.gitignore`

```gitignore
# Dependencies
node_modules/

# Build output
dist/

# Astro
.astro/

# Environment
.env
.env.*

# OS
.DS_Store
Thumbs.db
```

### Success Criteria:

#### Automated Verification:

- [x] Script is executable: `test -x scripts/deploy_astro.sh`
- [x] `cd astro-portfolio && npm run build` creates `dist/` directory
- [x] Build output contains HTML files

#### Manual Verification:

- [ ] `./scripts/deploy_astro.sh` uploads to S3 successfully
- [ ] Site accessible via S3 static website URL (or CloudFront when ready)

---

## Part B: HTMX Client Portal

---

## Phase 3.7: FastAPI Template Setup

### Overview

Add Jinja2 templating to the existing FastAPI client portal for HTMX-powered UI.

### Changes Required:

#### 1. Update requirements.txt

**File**: `backend/client_portal/requirements.txt`

```
fastapi>=0.109.0
mangum>=0.17.0
pydantic>=2.0.0
boto3>=1.34.0
python-jose[cryptography]>=3.3.0
jinja2>=3.1.0
python-multipart>=0.0.6
```

#### 2. Create templates directory structure

```bash
mkdir -p backend/client_portal/app/templates
mkdir -p backend/client_portal/app/static
```

#### 3. Update main.py with template support

**File**: `backend/client_portal/app/main.py` (replace existing)

```python
"""
Client Portal API + HTMX UI

FastAPI application for authenticated client access to photo albums.
Serves both JSON API and HTMX-powered HTML templates.
Wrapped with Mangum for AWS Lambda deployment.
"""
import os
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from mangum import Mangum
from pathlib import Path

from .routes import albums, portal
from .services.cognito import get_current_user

# Get the directory containing this file
BASE_DIR = Path(__file__).resolve().parent

# Initialize FastAPI
app = FastAPI(
    title="Katelynn's Photography Client Portal",
    description="Client portal for accessing photo albums",
    version="1.0.0",
)

# CORS middleware (for API access from Astro site)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restricted by API Gateway in production
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Templates setup
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

# Static files (CSS/JS for portal)
# Note: In Lambda, static files are bundled with the deployment
try:
    app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")
except RuntimeError:
    pass  # Directory might not exist in some environments

# Include routers
app.include_router(albums.router, prefix="/api", tags=["api"])
app.include_router(portal.router, tags=["portal"])


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "client-portal"}


@app.get("/api/me")
async def get_user_info(request: Request):
    """Get current user information (API endpoint)."""
    try:
        user = get_current_user(request)
        return {
            "email": user.get("email"),
            "name": user.get("name"),
            "sub": user.get("sub")
        }
    except Exception:
        return {"error": "Not authenticated"}


# Mangum handler for Lambda
handler = Mangum(app, lifespan="off")
```

### Success Criteria:

#### Automated Verification:

- [x] `pip install -r requirements.txt` succeeds
- [x] `python -c "from app.main import app"` works
- [x] Templates directory exists

#### Manual Verification:

- [ ] FastAPI app starts locally with template support

---

## Phase 3.8: HTMX Base Template and Login

### Overview

Create the base HTML template with HTMX and the login page.

### Changes Required:

#### 1. Create base template

**File**: `backend/client_portal/app/templates/base.html`

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>
      {% block title %}Client Portal{% endblock %} | Katelynn's Photography
    </title>

    <!-- HTMX -->
    <script
      src="https://unpkg.com/htmx.org@1.9.12"
      integrity="sha384-ujb1lZYygJmzgSwoxRggbCHcjc0rB2XoQrxeTUQyRjrOnlCoYta87iKBWq3EsdM2"
      crossorigin="anonymous"
    ></script>

    <!-- Tailwind CSS (CDN for simplicity, can switch to built CSS) -->
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
      tailwind.config = {
        theme: {
          extend: {
            colors: {
              primary: {
                50: "#fdf8f6",
                100: "#f2e8e5",
                200: "#eaddd7",
                300: "#e0cec7",
                400: "#d2bab0",
                500: "#bfa094",
                600: "#a18072",
                700: "#977669",
                800: "#846358",
                900: "#43302b",
              },
              accent: {
                DEFAULT: "#d4a574",
                dark: "#b8956a",
              },
            },
            fontFamily: {
              serif: ["Playfair Display", "Georgia", "serif"],
              sans: ["Lato", "Helvetica", "Arial", "sans-serif"],
            },
          },
        },
      };
    </script>

    <!-- Google Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;500;600&family=Lato:wght@300;400;700&display=swap"
      rel="stylesheet"
    />

    <style>
      body {
        font-family: "Lato", sans-serif;
      }
      h1,
      h2,
      h3,
      h4,
      h5,
      h6 {
        font-family: "Playfair Display", serif;
      }

      /* HTMX loading indicators */
      .htmx-indicator {
        opacity: 0;
        transition: opacity 200ms ease-in;
      }
      .htmx-request .htmx-indicator,
      .htmx-request.htmx-indicator {
        opacity: 1;
      }

      /* Loading spinner */
      .spinner {
        border: 2px solid #f3f3f3;
        border-top: 2px solid #d4a574;
        border-radius: 50%;
        width: 20px;
        height: 20px;
        animation: spin 1s linear infinite;
        display: inline-block;
      }
      @keyframes spin {
        0% {
          transform: rotate(0deg);
        }
        100% {
          transform: rotate(360deg);
        }
      }
    </style>

    {% block head %}{% endblock %}
  </head>
  <body class="bg-primary-50 min-h-screen">
    <!-- Navigation -->
    <nav class="bg-white border-b border-primary-200 px-4 py-4">
      <div class="max-w-6xl mx-auto flex items-center justify-between">
        <a
          href="/"
          class="text-xl font-serif text-primary-900 hover:text-accent transition-colors"
        >
          Katelynn's Photography
        </a>
        <div class="flex items-center gap-4">
          {% if user %}
          <span class="text-sm text-primary-600">{{ user.email }}</span>
          <button
            hx-post="/logout"
            hx-target="body"
            class="text-sm text-primary-600 hover:text-accent transition-colors"
          >
            Logout
          </button>
          {% else %}
          <a
            href="/client"
            class="text-sm text-primary-600 hover:text-accent transition-colors"
          >
            Login
          </a>
          {% endif %}
        </div>
      </div>
    </nav>

    <!-- Main Content -->
    <main class="max-w-6xl mx-auto px-4 py-8">
      {% block content %}{% endblock %}
    </main>

    <!-- Footer -->
    <footer class="bg-primary-900 text-primary-200 py-6 mt-auto">
      <div class="max-w-6xl mx-auto px-4 text-center text-sm">
        <p>
          &copy; {{ current_year }} Katelynn's Photography. All rights reserved.
        </p>
        <p class="mt-2">
          <a href="/" class="hover:text-accent transition-colors"
            >Back to Main Site</a
          >
        </p>
      </div>
    </footer>

    {% block scripts %}{% endblock %}
  </body>
</html>
```

#### 2. Create login template

**File**: `backend/client_portal/app/templates/login.html`

```html
{% extends "base.html" %} {% block title %}Client Login{% endblock %} {% block
content %}
<div class="max-w-md mx-auto mt-12">
  <div class="bg-white rounded-sm shadow-lg p-8">
    <h1 class="text-2xl font-serif text-primary-900 text-center mb-6">
      Client Login
    </h1>

    <p class="text-primary-600 text-sm text-center mb-8">
      Access your photo galleries and downloads.
    </p>

    {% if error %}
    <div class="bg-red-100 text-red-800 p-4 rounded-sm mb-6 text-sm">
      {{ error }}
    </div>
    {% endif %}

    <form
      hx-post="/login"
      hx-target="#login-result"
      hx-indicator="#login-spinner"
      class="space-y-6"
    >
      <div>
        <label
          for="email"
          class="block text-sm font-medium text-primary-700 mb-2"
        >
          Email Address
        </label>
        <input
          type="email"
          id="email"
          name="email"
          required
          class="w-full px-4 py-3 border border-primary-300 rounded-sm
                           focus:ring-2 focus:ring-accent focus:border-accent outline-none"
          placeholder="your@email.com"
        />
      </div>

      <div>
        <label
          for="password"
          class="block text-sm font-medium text-primary-700 mb-2"
        >
          Password
        </label>
        <input
          type="password"
          id="password"
          name="password"
          required
          class="w-full px-4 py-3 border border-primary-300 rounded-sm
                           focus:ring-2 focus:ring-accent focus:border-accent outline-none"
          placeholder="••••••••"
        />
      </div>

      <button
        type="submit"
        class="w-full bg-accent text-white py-3 rounded-sm font-medium
                       hover:bg-accent-dark transition-colors disabled:opacity-50"
      >
        <span class="htmx-indicator" id="login-spinner">
          <span class="spinner mr-2"></span>
        </span>
        Sign In
      </button>
    </form>

    <div id="login-result" class="mt-4"></div>

    <div class="mt-6 pt-6 border-t border-primary-200 text-center">
      <p class="text-sm text-primary-600">
        Don't have access? Contact us after your session to receive your login
        credentials.
      </p>
    </div>
  </div>
</div>
{% endblock %}
```

#### 3. Create portal routes

**File**: `backend/client_portal/app/routes/portal.py`

```python
"""
Portal Routes

HTMX-powered HTML routes for the client portal.
"""
import os
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Request, Response, Form, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
import boto3
from botocore.exceptions import ClientError

from ..services.cognito import get_current_user, verify_cognito_token
from ..services.s3 import S3Service

router = APIRouter()
BASE_DIR = Path(__file__).resolve().parent.parent
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

# Cognito client
cognito_client = boto3.client("cognito-idp", region_name="us-east-2")
COGNITO_USER_POOL_ID = os.environ.get("COGNITO_USER_POOL_ID", "us-east-2_bn71poxi6")
COGNITO_CLIENT_ID = os.environ.get("COGNITO_CLIENT_ID", "6a5h8p858dg9laj544ijvu9gro")

s3_service = S3Service()


def get_template_context(request: Request, user: Optional[dict] = None) -> dict:
    """Get common template context."""
    return {
        "request": request,
        "user": user,
        "current_year": datetime.now().year,
    }


@router.get("/client", response_class=HTMLResponse)
async def login_page(request: Request):
    """Render login page."""
    # Check if already authenticated (cookie-based for HTMX)
    token = request.cookies.get("access_token")
    if token:
        # Verify token and redirect to dashboard
        user = verify_cognito_token(token)
        if user:
            return RedirectResponse(url="/client/dashboard", status_code=302)

    context = get_template_context(request)
    return templates.TemplateResponse("login.html", context)


@router.post("/login")
async def login(
    request: Request,
    email: str = Form(...),
    password: str = Form(...)
):
    """Handle login form submission via HTMX."""
    try:
        # Authenticate with Cognito
        response = cognito_client.initiate_auth(
            ClientId=COGNITO_CLIENT_ID,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": email,
                "PASSWORD": password,
            }
        )

        # Get tokens
        auth_result = response.get("AuthenticationResult", {})
        access_token = auth_result.get("AccessToken")

        if not access_token:
            # Challenge required (e.g., password change)
            challenge = response.get("ChallengeName")
            if challenge == "NEW_PASSWORD_REQUIRED":
                return HTMLResponse(
                    content="""
                    <div class="bg-yellow-100 text-yellow-800 p-4 rounded-sm text-sm">
                        Please set a new password. Contact us for assistance.
                    </div>
                    """,
                    status_code=200
                )
            return HTMLResponse(
                content="""
                <div class="bg-red-100 text-red-800 p-4 rounded-sm text-sm">
                    Authentication failed. Please try again.
                </div>
                """,
                status_code=200
            )

        # Set cookie and redirect via HTMX
        response = HTMLResponse(
            content="",
            status_code=200,
            headers={
                "HX-Redirect": "/client/dashboard"
            }
        )
        response.set_cookie(
            key="access_token",
            value=access_token,
            httponly=True,
            secure=True,
            samesite="lax",
            max_age=3600  # 1 hour
        )
        return response

    except cognito_client.exceptions.NotAuthorizedException:
        return HTMLResponse(
            content="""
            <div class="bg-red-100 text-red-800 p-4 rounded-sm text-sm">
                Invalid email or password. Please try again.
            </div>
            """,
            status_code=200
        )
    except cognito_client.exceptions.UserNotFoundException:
        return HTMLResponse(
            content="""
            <div class="bg-red-100 text-red-800 p-4 rounded-sm text-sm">
                No account found with that email address.
            </div>
            """,
            status_code=200
        )
    except Exception as e:
        print(f"Login error: {e}")
        return HTMLResponse(
            content="""
            <div class="bg-red-100 text-red-800 p-4 rounded-sm text-sm">
                An error occurred. Please try again later.
            </div>
            """,
            status_code=200
        )


@router.post("/logout")
async def logout(request: Request):
    """Handle logout."""
    response = HTMLResponse(
        content="",
        status_code=200,
        headers={
            "HX-Redirect": "/client"
        }
    )
    response.delete_cookie(key="access_token")
    return response


@router.get("/client/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Render client dashboard with albums."""
    token = request.cookies.get("access_token")
    if not token:
        return RedirectResponse(url="/client", status_code=302)

    user = verify_cognito_token(token)
    if not user:
        response = RedirectResponse(url="/client", status_code=302)
        response.delete_cookie(key="access_token")
        return response

    # Get user's albums
    try:
        albums = s3_service.list_user_albums(user.get("email", ""))
    except Exception as e:
        print(f"Error listing albums: {e}")
        albums = []

    context = get_template_context(request, user)
    context["albums"] = albums
    return templates.TemplateResponse("dashboard.html", context)


@router.get("/client/albums/{album_id}", response_class=HTMLResponse)
async def album_detail(request: Request, album_id: str):
    """Render album detail page with files."""
    token = request.cookies.get("access_token")
    if not token:
        return RedirectResponse(url="/client", status_code=302)

    user = verify_cognito_token(token)
    if not user:
        response = RedirectResponse(url="/client", status_code=302)
        response.delete_cookie(key="access_token")
        return response

    user_email = user.get("email", "")

    # Get album details
    album = s3_service.get_album_details(user_email, album_id)
    if not album:
        raise HTTPException(status_code=404, detail="Album not found")

    # Get files with presigned URLs
    files = s3_service.list_album_files(user_email, album_id)

    context = get_template_context(request, user)
    context["album"] = album
    context["files"] = files
    return templates.TemplateResponse("album_detail.html", context)
```

#### 4. Update cognito.py with token verification

**File**: `backend/client_portal/app/services/cognito.py` (update)

```python
"""
Cognito Authentication Service

Handles JWT token verification for API Gateway Cognito authorizer
and cookie-based authentication for HTMX portal.
"""
import os
from typing import Optional
from fastapi import HTTPException, Request
import boto3
from botocore.exceptions import ClientError

# Cognito client
cognito_client = boto3.client("cognito-idp", region_name="us-east-2")
COGNITO_USER_POOL_ID = os.environ.get("COGNITO_USER_POOL_ID", "us-east-2_bn71poxi6")


def get_current_user(request: Request) -> dict:
    """
    Extract user information from API Gateway request context.
    For API Gateway JWT authorizer flow.
    """
    # API Gateway v2 (HTTP API) puts JWT claims in requestContext.authorizer.jwt.claims
    event = request.scope.get("aws.event", {})
    if event:
        authorizer = event.get("requestContext", {}).get("authorizer", {})
        jwt_claims = authorizer.get("jwt", {}).get("claims", {})

        if jwt_claims:
            return {
                "sub": jwt_claims.get("sub"),
                "email": jwt_claims.get("email"),
                "name": jwt_claims.get("name"),
                "cognito_username": jwt_claims.get("cognito:username")
            }

    # Fallback: Check cookie for HTMX portal
    token = request.cookies.get("access_token")
    if token:
        user = verify_cognito_token(token)
        if user:
            return user

    # Fallback: Check request headers for testing
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        # For local dev/testing only
        return {
            "sub": "test-user",
            "email": "test@example.com",
            "name": "Test User"
        }

    raise HTTPException(
        status_code=401,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"}
    )


def verify_cognito_token(token: str) -> Optional[dict]:
    """
    Verify Cognito access token and return user info.
    Used for cookie-based HTMX authentication.
    """
    try:
        response = cognito_client.get_user(AccessToken=token)

        # Extract user attributes
        attributes = {attr["Name"]: attr["Value"] for attr in response.get("UserAttributes", [])}

        return {
            "sub": attributes.get("sub"),
            "email": attributes.get("email"),
            "name": attributes.get("name"),
            "cognito_username": response.get("Username")
        }
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        if error_code in ("NotAuthorizedException", "ExpiredTokenException"):
            return None
        print(f"Cognito verification error: {e}")
        return None
    except Exception as e:
        print(f"Token verification error: {e}")
        return None
```

### Success Criteria:

#### Automated Verification:

- [x] `python -c "from app.routes.portal import router"` succeeds
- [x] Template files exist in templates directory
- [x] No Python syntax errors

#### Manual Verification:

- [ ] Login page renders at `/client`
- [ ] Login form submits via HTMX
- [ ] Invalid credentials show error message
- [ ] Successful login redirects to dashboard

---

## Phase 3.9: HTMX Dashboard and Album Pages

### Overview

Create the dashboard and album detail templates for the client portal.

### Changes Required:

#### 1. Create dashboard template

**File**: `backend/client_portal/app/templates/dashboard.html`

```html
{% extends "base.html" %} {% block title %}My Albums{% endblock %} {% block
content %}
<div class="mb-8">
  <h1 class="text-3xl font-serif text-primary-900 mb-2">
    Welcome, {{ user.name or user.email }}
  </h1>
  <p class="text-primary-600">
    Here are your photo albums. Click on any album to view and download your
    photos.
  </p>
</div>

{% if albums %}
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
  {% for album in albums %}
  <a
    href="/client/albums/{{ album.id }}"
    class="bg-white rounded-sm shadow-md hover:shadow-lg transition-shadow overflow-hidden group"
  >
    <div class="aspect-video bg-primary-200 relative overflow-hidden">
      <!-- Album thumbnail placeholder -->
      <div
        class="absolute inset-0 flex items-center justify-center text-primary-400"
      >
        <svg
          class="w-16 h-16"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
          />
        </svg>
      </div>
    </div>
    <div class="p-4">
      <h2
        class="text-lg font-serif text-primary-900 group-hover:text-accent transition-colors"
      >
        {{ album.name }}
      </h2>
      <div
        class="flex items-center justify-between mt-2 text-sm text-primary-600"
      >
        <span>{{ album.photo_count }} photos</span>
        {% if album.created_at %}
        <span>{{ album.created_at[:10] }}</span>
        {% endif %}
      </div>
    </div>
  </a>
  {% endfor %}
</div>
{% else %}
<div class="bg-white rounded-sm shadow-md p-8 text-center">
  <svg
    class="w-16 h-16 mx-auto text-primary-300 mb-4"
    fill="none"
    stroke="currentColor"
    viewBox="0 0 24 24"
  >
    <path
      stroke-linecap="round"
      stroke-linejoin="round"
      stroke-width="1.5"
      d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
    />
  </svg>
  <h2 class="text-xl font-serif text-primary-900 mb-2">No Albums Yet</h2>
  <p class="text-primary-600">
    Your photo albums will appear here once they're ready. Check back soon!
  </p>
</div>
{% endif %} {% endblock %}
```

#### 2. Create album detail template

**File**: `backend/client_portal/app/templates/album_detail.html`

```html
{% extends "base.html" %} {% block title %}{{ album.name }}{% endblock %} {%
block content %}
<div class="mb-8">
  <a
    href="/client/dashboard"
    class="text-accent hover:text-accent-dark transition-colors text-sm mb-4 inline-block"
  >
    &larr; Back to Albums
  </a>
  <h1 class="text-3xl font-serif text-primary-900 mb-2">{{ album.name }}</h1>
  <p class="text-primary-600">
    {{ album.photo_count }} photos available for download
  </p>
</div>

{% if files %}
<!-- Bulk Download Section -->
<div class="bg-white rounded-sm shadow-md p-6 mb-8">
  <div
    class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4"
  >
    <div>
      <h2 class="text-lg font-serif text-primary-900">Download All Photos</h2>
      <p class="text-sm text-primary-600">
        Click each photo below to download individually, or use the links.
      </p>
    </div>
  </div>
</div>

<!-- Photo Grid -->
<div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
  {% for file in files %}
  <div class="bg-white rounded-sm shadow-md overflow-hidden group">
    <div class="aspect-square bg-primary-200 relative overflow-hidden">
      <!-- Image preview (using presigned URL) -->
      <img
        src="{{ file.download_url }}"
        alt="{{ file.name }}"
        class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
        loading="lazy"
      />
      <!-- Download overlay -->
      <a
        href="{{ file.download_url }}"
        download="{{ file.name }}"
        class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100
                       transition-opacity flex items-center justify-center"
      >
        <span
          class="bg-white text-primary-900 px-4 py-2 rounded-sm text-sm font-medium"
        >
          Download
        </span>
      </a>
    </div>
    <div class="p-3">
      <p class="text-sm text-primary-800 truncate" title="{{ file.name }}">
        {{ file.name }}
      </p>
      <p class="text-xs text-primary-500">
        {{ (file.size / 1024 / 1024) | round(1) }} MB
      </p>
    </div>
  </div>
  {% endfor %}
</div>
{% else %}
<div class="bg-white rounded-sm shadow-md p-8 text-center">
  <svg
    class="w-16 h-16 mx-auto text-primary-300 mb-4"
    fill="none"
    stroke="currentColor"
    viewBox="0 0 24 24"
  >
    <path
      stroke-linecap="round"
      stroke-linejoin="round"
      stroke-width="1.5"
      d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
    />
  </svg>
  <h2 class="text-xl font-serif text-primary-900 mb-2">No Photos Yet</h2>
  <p class="text-primary-600">
    Photos are being uploaded to this album. Check back soon!
  </p>
</div>
{% endif %} {% endblock %}
```

### Success Criteria:

#### Automated Verification:

- [x] Template files exist and have valid Jinja2 syntax
- [x] No undefined variables in templates

#### Manual Verification:

- [ ] Dashboard displays user's albums
- [ ] Album detail page shows photo grid
- [ ] Download links work (presigned URLs)
- [ ] Responsive layout on mobile devices

---

## Phase 3.10: Client Portal Deployment

### Overview

Update the Lambda deployment to include templates and test end-to-end.

### Changes Required:

#### 1. Update deploy script for client portal

The existing `scripts/deploy_lambda.sh` already handles the client_portal deployment. Ensure templates are included:

```bash
# The cp -r command already copies the entire directory structure
cp -r "$BACKEND_DIR/$source_dir/"* "$BUILD_DIR/$source_dir/"
```

#### 2. Add API Gateway routes for portal pages

**File**: `terraform/lambda.tf` (additions)

```hcl
# Portal page routes (HTML responses)
resource "aws_apigatewayv2_route" "portal_login" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /client"
  target    = "integrations/${aws_apigatewayv2_integration.client_portal.id}"
}

resource "aws_apigatewayv2_route" "portal_login_post" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /login"
  target    = "integrations/${aws_apigatewayv2_integration.client_portal.id}"
}

resource "aws_apigatewayv2_route" "portal_logout" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /logout"
  target    = "integrations/${aws_apigatewayv2_integration.client_portal.id}"
}

resource "aws_apigatewayv2_route" "portal_dashboard" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /client/dashboard"
  target    = "integrations/${aws_apigatewayv2_integration.client_portal.id}"
}

resource "aws_apigatewayv2_route" "portal_album_detail" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /client/albums/{album_id}"
  target    = "integrations/${aws_apigatewayv2_integration.client_portal.id}"
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform validate` succeeds
- [x] Deploy script includes templates directory
- [ ] `terraform apply` succeeds
- [ ] `./scripts/deploy_lambda.sh client_portal` succeeds

#### Manual Verification:

- [ ] `/client` login page accessible via API Gateway URL
- [ ] Login with Cognito credentials works
- [ ] Dashboard shows albums after login
- [ ] Album detail page loads with photos
- [ ] Photo downloads work via presigned URLs
- [ ] Logout clears session and redirects to login

**Implementation Note**: After completing this phase, perform full end-to-end testing of the client portal flow.

---

## Testing Strategy

### Astro Public Site Testing

1. **Build Verification**:

   ```bash
   cd astro-portfolio
   npm run build
   ```

2. **Local Preview**:

   ```bash
   npm run preview
   ```

3. **Accessibility Check**:
   - Run Lighthouse audit
   - Verify keyboard navigation
   - Check color contrast

4. **Mobile Testing**:
   - Test on various screen sizes
   - Verify touch interactions

### HTMX Client Portal Testing

1. **Authentication Flow**:
   - Login with valid credentials → Dashboard
   - Login with invalid credentials → Error message
   - Access protected page without auth → Redirect to login
   - Logout → Clear session, redirect to login

2. **Album Access**:
   - View albums list
   - Open album detail
   - Download individual photo
   - Verify presigned URLs expire correctly

3. **HTMX Behavior**:
   - Form submissions don't full-page reload
   - Loading indicators display during requests
   - Error messages appear inline

### Manual Testing Checklist

**Public Site:**

- [ ] Landing page hero displays correctly
- [ ] Portfolio gallery filter works
- [ ] Lightbox opens and navigates
- [ ] Contact form submits successfully
- [ ] Mobile navigation works
- [ ] All images load (once added to S3)

**Client Portal:**

- [ ] Login with test Cognito user
- [ ] See albums on dashboard
- [ ] Open album and see photos
- [ ] Download photo successfully
- [ ] Logout clears session
- [ ] Unauthorized access redirects

---

## Performance Considerations

### Astro Site

- **Image Optimization**: Use Astro's built-in Image component for automatic WebP/AVIF
- **Code Splitting**: Astro handles this automatically
- **Cache Headers**: Set long cache for assets, short for HTML

### HTMX Portal

- **Presigned URL Caching**: URLs valid for 1 hour
- **Image Lazy Loading**: Use native `loading="lazy"`
- **HTMX Request Indicators**: Show loading state during API calls

---

## Rollback Plan

### Astro Site

1. S3 versioning enabled - can restore previous versions
2. Keep previous build locally before deploying
3. CloudFront invalidation if needed

### HTMX Portal

1. Lambda versions available in AWS Console
2. Terraform can recreate resources
3. API Gateway routes can be disabled individually

---

## References

- Master plan: `thoughts/shared/plans/2026-01-08-build-website-master-plan.md`
- Phase 1 plan: `thoughts/shared/plans/2026-01-08-phase1-terraform-infrastructure.md`
- Phase 2 plan: `thoughts/shared/plans/2026-01-08-phase2-backend-lambda.md`
- Astro docs: https://docs.astro.build/
- HTMX docs: https://htmx.org/docs/
- Tailwind CSS: https://tailwindcss.com/docs

---

## Summary

Phase 3 creates the complete frontend:

**Part A (Astro):** Public portfolio with landing page, galleries, about, and contact form - deployed to S3/CloudFront

**Part B (HTMX):** Client portal with login, dashboard, and album downloads - served via Lambda/API Gateway

Total new files: ~20 (Astro components/pages + HTMX templates + deployment scripts)
