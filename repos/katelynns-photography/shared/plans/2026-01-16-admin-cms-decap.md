# Admin CMS with Decap CMS + DecapBridge Implementation Plan

## Overview

Add a content management system that allows site admins (2 users) to update photos and text throughout the site without code changes. Uses Decap CMS for the editing interface and DecapBridge for authentication (since we're on AWS Amplify, not Netlify).

## Current State Analysis

### Architecture

- **Frontend**: Astro 5.16.7 static site on AWS Amplify
- **Content**: All text/images hardcoded in `.astro` files
- **Images**: 7 static images in `frontend/public/images/`
- **No database** - no content storage layer exists
- **No content collections** - Astro content collections not yet used

### Pages Requiring Migration

| Page              | Editable Content                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------- |
| `index.astro`     | Hero text, About section, 5 "How It Works" steps, 3 recent wedding cards, 1 testimonial, CTA text |
| `about.astro`     | Page title, 5 bio paragraphs, about photo                                                         |
| `pricing.astro`   | Page intro, custom packages description                                                           |
| `portfolio.astro` | 5 wedding gallery items (title + image each)                                                      |
| `contact.astro`   | Page intro, email, location, response time, booking info                                          |

### Current Images (7 total)

- `hero-bg.jpg` - Homepage hero background
- `about-full.jpg` - About page photo
- `placeholder-wedding-1.jpg` through `placeholder-wedding-5.jpg` - Portfolio/recent weddings

## Desired End State

1. Admin visits `yoursite.com/admin/` and logs in via DecapBridge
2. Admin sees a dashboard with editable content collections:
   - **Site Settings** (hero, CTA sections)
   - **About Page** (bio, photo)
   - **Pricing Page** (descriptions)
   - **Galleries** (wedding portfolio items)
   - **Testimonials** (client quotes)
   - **Process Steps** ("How It Works" section)
3. Admin edits text/uploads images through the CMS interface
4. Changes are committed to git, triggering Amplify rebuild
5. Site updates automatically within minutes

### Verification

- [ ] Admin can log in at `/admin/`
- [ ] All text content is editable through CMS
- [ ] Image uploads work and appear on site
- [ ] Git commits appear in repo after edits
- [ ] Amplify auto-deploys on commit

## What We're NOT Doing

- NOT building custom admin UI (using Decap CMS)
- NOT adding a database (git-based content)
- NOT enabling client portal editing (admin only)
- NOT migrating client album management (stays as-is in S3)
- NOT adding SSR - site remains static with build-time content fetching

## Implementation Approach

We'll use Astro's Content Collections feature to store content as JSON/YAML files that Decap CMS can edit. The build process reads these files and generates static pages.

**Tech Stack Addition:**

- Decap CMS (via unpkg CDN)
- DecapBridge (hosted auth service, free tier)
- Astro Content Collections (built-in)

---

## Phase 1: Set Up Decap CMS + DecapBridge Auth

### Overview

Install Decap CMS, configure DecapBridge authentication, and verify admin login works.

### Changes Required:

#### 1. Create Decap CMS Admin Page

**File**: `frontend/src/pages/admin.astro`

```astro
---
// Admin page - serves Decap CMS interface
// Uses DecapBridge for authentication
---
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex" />
    <title>Admin - Katelynn's Photography</title>
  </head>
  <body>
    <script src="https://unpkg.com/decap-cms@^3.3/dist/decap-cms.js"></script>
  </body>
</html>
```

#### 2. Create Decap CMS Configuration

**File**: `frontend/public/admin/config.yml`

```yaml
backend:
  name: decap-bridge
  # DecapBridge will provide the specific configuration after signup
  # The actual values come from DecapBridge dashboard
  repo: aw-jwalker/katelynns-photography
  branch: main
  base_url: https://decapbridge.com
  # site_id will be provided by DecapBridge

# Media files configuration
media_folder: "frontend/public/images"
public_folder: "/images"

# Slug settings
slug:
  encoding: "ascii"
  clean_accents: true
  sanitize_replacement: "-"

# Collections will be added in Phase 2
collections: []
```

#### 3. Sign Up for DecapBridge

**Manual Step**:

1. Go to https://decapbridge.com
2. Create account
3. Add site with GitHub repo `aw-jwalker/katelynns-photography`
4. Copy the provided `site_id` value
5. Update `config.yml` with DecapBridge credentials
6. Invite the 2 admin users via DecapBridge dashboard

### Success Criteria:

#### Automated Verification:

- [x] `frontend/src/pages/admin.astro` exists
- [x] `frontend/public/admin/config.yml` exists
- [x] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:

- [ ] Navigate to `https://[site-url]/admin/`
- [ ] DecapBridge login screen appears
- [ ] Can log in with admin credentials
- [ ] Empty CMS dashboard loads (no collections yet)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that DecapBridge login works before proceeding to the next phase.

---

## Phase 2: Create Content Collections Structure

### Overview

Set up Astro content collections and define the content schemas that Decap CMS will edit.

### Changes Required:

#### 1. Create Content Collection Config

**File**: `frontend/src/content/config.ts`

```typescript
import { defineCollection, z } from "astro:content";

// Site-wide settings (hero, CTAs, etc.)
const siteSettings = defineCollection({
  type: "data",
  schema: z.object({
    hero: z.object({
      title: z.string(),
      subtitle: z.string(),
      backgroundImage: z.string(),
    }),
    outdoorSection: z.object({
      heading: z.string(),
      body: z.string(),
      buttonText: z.string(),
    }),
    ctaSection: z.object({
      heading: z.string(),
      buttonText: z.string(),
    }),
  }),
});

// About page content
const about = defineCollection({
  type: "data",
  schema: z.object({
    pageTitle: z.string(),
    photo: z.string(),
    paragraphs: z.array(z.string()),
  }),
});

// Pricing page content
const pricing = defineCollection({
  type: "data",
  schema: z.object({
    pageTitle: z.string(),
    pageIntro: z.string(),
    packagesHeading: z.string(),
    packagesDescription: z.array(z.string()),
    ctaHeading: z.string(),
    ctaButtonText: z.string(),
  }),
});

// Contact page content
const contact = defineCollection({
  type: "data",
  schema: z.object({
    pageTitle: z.string(),
    pageIntro: z.string(),
    email: z.string(),
    location: z.string(),
    responseTime: z.string(),
    bookingInfo: z.string(),
  }),
});

// Gallery items (portfolio)
const galleries = defineCollection({
  type: "content",
  schema: z.object({
    title: z.string(),
    image: z.string(),
    order: z.number(),
    featured: z.boolean().default(false),
  }),
});

// Testimonials
const testimonials = defineCollection({
  type: "content",
  schema: z.object({
    quote: z.string(),
    author: z.string(),
    featured: z.boolean().default(false),
    order: z.number(),
  }),
});

// Process steps ("How It Works")
const processSteps = defineCollection({
  type: "data",
  schema: z.object({
    steps: z.array(
      z.object({
        number: z.number(),
        title: z.string(),
        description: z.string(),
      }),
    ),
  }),
});

export const collections = {
  "site-settings": siteSettings,
  about: about,
  pricing: pricing,
  contact: contact,
  galleries: galleries,
  testimonials: testimonials,
  "process-steps": processSteps,
};
```

#### 2. Create Initial Content Files

**File**: `frontend/src/content/site-settings/home.json`

```json
{
  "hero": {
    "title": "OHIO OUTDOOR WEDDING PHOTOGRAPHER FOR NATURE-LOVING COUPLES",
    "subtitle": "IF YOU CAN'T IMAGINE YOUR WEDDING ANYWHERE OTHER THAN UNDER THE SUN, YOU'RE IN THE RIGHT PLACE.",
    "backgroundImage": "/images/hero-bg.jpg"
  },
  "outdoorSection": {
    "heading": "You don't have to get married inside a stuffy, dark building.",
    "body": "There are so many beautiful outdoor wedding venues in Columbus and throughout Ohio that will make you want to run barefoot through a field.",
    "buttonText": "CHECK OUT MY FAVS"
  },
  "ctaSection": {
    "heading": "LET'S CAPTURE YOUR OUTDOOR WEDDING",
    "buttonText": "SAY HI!"
  }
}
```

**File**: `frontend/src/content/about/main.json`

```json
{
  "pageTitle": "About Me",
  "photo": "/images/about-full.jpg",
  "paragraphs": [
    "Hi, I'm Katelynn — an outdoor-loving wedding photographer based in Columbus, Ohio.",
    "If the outdoors feels like home and your idea of a perfect day includes fresh air, sun-soaked trails, or saying \"I do\" under the open sky… we'll get along just fine.",
    "I specialize in photographing couples who feel most alive outside — whether you're planning an intimate backyard ceremony, a celebration at a nature-inspired venue, or a mountaintop elopement. Your connection, your joy, and your love for nature are what I'm here to document — authentically and beautifully.",
    "My approach is personal, flexible, and focused entirely on you. Need help planning your timeline? I've got you. Want someone who will bustle your dress, grab snacks, or calm nerves before the ceremony? I'm there. I believe wedding photography should feel effortless, like being cared for by a friend who also just happens to take incredible photos.",
    "When you step in front of my camera, I'll guide you with gentle direction so you feel natural and confident. Your job? Just be wildly in love with your favorite person. I'll take care of the rest."
  ]
}
```

**File**: `frontend/src/content/pricing/main.json`

```json
{
  "pageTitle": "Pricing",
  "pageIntro": "Every wedding is unique, and so should be your photography package. Contact me to discuss custom packages tailored to your vision and needs.",
  "packagesHeading": "Custom Packages",
  "packagesDescription": [
    "I believe in creating photography packages that fit your specific needs and vision. After we chat about your wedding day, I'll create a couple of package options based on everything we discussed. You'll have the chance to look them over, ask questions, or request changes. These packages are here to serve you!",
    "Packages typically include coverage time, number of photographers, edited high-resolution images, online gallery access, and more. Let's talk about what matters most to you."
  ],
  "ctaHeading": "ready to get started?",
  "ctaButtonText": "heck yes! I'm ready!"
}
```

**File**: `frontend/src/content/contact/main.json`

```json
{
  "pageTitle": "Inquire",
  "pageIntro": "I'd love to hear about your upcoming occasion. Fill out the form below and I'll get back to you within 24-48 hours.",
  "email": "hello@katelynnsphotography.com",
  "location": "Columbus, Ohio",
  "responseTime": "I typically respond to inquiries within 24-48 hours during business days. For urgent matters, please mention it in your message.",
  "bookingInfo": "I book weddings and events 6-12 months in advance. Portrait sessions can often be scheduled within 2-4 weeks. Early booking is recommended for peak seasons (May-October)."
}
```

**File**: `frontend/src/content/process-steps/main.json`

```json
{
  "steps": [
    {
      "number": 1,
      "title": "set up a phone call",
      "description": "After you inquire through my website, we'll set up a phone call to chat, get to know each other and talk all about your vision for your day! I have a whole bunch of questions I am going to ask you to help draw out all of your wants and needs for the day. This is a great time to ask me any questions you have too!"
    },
    {
      "number": 2,
      "title": "the planning process",
      "description": "After our call, I will create a couple packaging options based on everything we talked about. You will have the chance to look over them, ask any questions or even ask to see anything changed. These packages are here to serve you! You shouldn't have to settle for anything less than what you want."
    },
    {
      "number": 3,
      "title": "making it official",
      "description": "Once you've picked the package right for you, I will send over the contract and deposit info. We will officially be set once both are completed! (I'll be doing my happy dance)"
    },
    {
      "number": 4,
      "title": "as the day approaches",
      "description": "Once we get closer to the day, we will hop on another call to discuss your finalized schedule, family photo list and any other special photo requests you have."
    },
    {
      "number": 5,
      "title": "take some beautiful photos",
      "description": "When the day is FINALLY here, you will relax and laugh with each other while I direct and guide you throughout the whole time with prompts that draw out your love. Rain or shine, we will have so much fun!"
    }
  ]
}
```

**File**: `frontend/src/content/galleries/wedding-at-the-brook.md`

```markdown
---
title: "WEDDING AT THE BROOK"
image: "/images/placeholder-wedding-1.jpg"
order: 1
featured: true
---
```

**File**: `frontend/src/content/galleries/ohio-backyard-wedding.md`

```markdown
---
title: "OHIO BACKYARD WEDDING"
image: "/images/placeholder-wedding-2.jpg"
order: 2
featured: true
---
```

**File**: `frontend/src/content/galleries/columbus-courthouse-elopement.md`

```markdown
---
title: "COLUMBUS ELOPEMENT AT THE COURTHOUSE"
image: "/images/placeholder-wedding-3.jpg"
order: 3
featured: true
---
```

**File**: `frontend/src/content/galleries/park-of-roses.md`

```markdown
---
title: "WEDDING AT THE PARK OF ROSES"
image: "/images/placeholder-wedding-4.jpg"
order: 4
featured: false
---
```

**File**: `frontend/src/content/galleries/north-bank-park.md`

```markdown
---
title: "WEDDING AT NORTH BANK PARK PAVILION"
image: "/images/placeholder-wedding-5.jpg"
order: 5
featured: false
---
```

**File**: `frontend/src/content/testimonials/abby-max.md`

```markdown
---
quote: "I've seen dozens of engagement shoots of couples doing lovely poses and smiling contentedly at the camera. I knew going into our session that my fiancé and I were not that couple, but I wasn't prepared for the absolute unbridled joy, laughter, and love that Katelynn would capture. From prompts that allowed us to move around and be silly, to a willingness to shoot our photos in the pouring rain, Katelynn was an absolute dream to work with. If you're looking for a photographer, stop looking. You found her."
author: "ABBY & MAX"
featured: true
order: 1
---
```

### Success Criteria:

#### Automated Verification:

- [x] All content files exist in `frontend/src/content/`
- [x] TypeScript compiles: `cd frontend && npx astro check` (pre-existing errors in other components, content collections fine)
- [x] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:

- [ ] Content files contain accurate migrated content from original pages

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to the next phase.

---

## Phase 3: Update Decap CMS Config with Collections

### Overview

Configure Decap CMS to know about our content collections so admins can edit them.

### Changes Required:

#### 1. Update Decap CMS Configuration

**File**: `frontend/public/admin/config.yml`

```yaml
backend:
  name: decap-bridge
  repo: aw-jwalker/katelynns-photography
  branch: main
  base_url: https://decapbridge.com
  # site_id: [FROM DECAPBRIDGE DASHBOARD]

media_folder: "frontend/public/images"
public_folder: "/images"

slug:
  encoding: "ascii"
  clean_accents: true
  sanitize_replacement: "-"

collections:
  # Site Settings (homepage hero, CTAs)
  - name: "site-settings"
    label: "Site Settings"
    files:
      - name: "home"
        label: "Homepage Settings"
        file: "frontend/src/content/site-settings/home.json"
        fields:
          - label: "Hero Section"
            name: "hero"
            widget: "object"
            fields:
              - { label: "Title", name: "title", widget: "string" }
              - { label: "Subtitle", name: "subtitle", widget: "string" }
              - {
                  label: "Background Image",
                  name: "backgroundImage",
                  widget: "image",
                }
          - label: "Outdoor Section"
            name: "outdoorSection"
            widget: "object"
            fields:
              - { label: "Heading", name: "heading", widget: "string" }
              - { label: "Body Text", name: "body", widget: "text" }
              - { label: "Button Text", name: "buttonText", widget: "string" }
          - label: "CTA Section"
            name: "ctaSection"
            widget: "object"
            fields:
              - { label: "Heading", name: "heading", widget: "string" }
              - { label: "Button Text", name: "buttonText", widget: "string" }

  # About Page
  - name: "about"
    label: "About Page"
    files:
      - name: "main"
        label: "About Content"
        file: "frontend/src/content/about/main.json"
        fields:
          - { label: "Page Title", name: "pageTitle", widget: "string" }
          - { label: "Photo", name: "photo", widget: "image" }
          - label: "Bio Paragraphs"
            name: "paragraphs"
            widget: "list"
            field: { label: "Paragraph", name: "paragraph", widget: "text" }

  # Pricing Page
  - name: "pricing"
    label: "Pricing Page"
    files:
      - name: "main"
        label: "Pricing Content"
        file: "frontend/src/content/pricing/main.json"
        fields:
          - { label: "Page Title", name: "pageTitle", widget: "string" }
          - { label: "Page Intro", name: "pageIntro", widget: "text" }
          - {
              label: "Packages Heading",
              name: "packagesHeading",
              widget: "string",
            }
          - label: "Packages Description"
            name: "packagesDescription"
            widget: "list"
            field: { label: "Paragraph", name: "paragraph", widget: "text" }
          - { label: "CTA Heading", name: "ctaHeading", widget: "string" }
          - {
              label: "CTA Button Text",
              name: "ctaButtonText",
              widget: "string",
            }

  # Contact Page
  - name: "contact"
    label: "Contact Page"
    files:
      - name: "main"
        label: "Contact Content"
        file: "frontend/src/content/contact/main.json"
        fields:
          - { label: "Page Title", name: "pageTitle", widget: "string" }
          - { label: "Page Intro", name: "pageIntro", widget: "text" }
          - { label: "Email Address", name: "email", widget: "string" }
          - { label: "Location", name: "location", widget: "string" }
          - {
              label: "Response Time Info",
              name: "responseTime",
              widget: "text",
            }
          - { label: "Booking Info", name: "bookingInfo", widget: "text" }

  # Process Steps
  - name: "process-steps"
    label: "How It Works"
    files:
      - name: "main"
        label: "Process Steps"
        file: "frontend/src/content/process-steps/main.json"
        fields:
          - label: "Steps"
            name: "steps"
            widget: "list"
            fields:
              - {
                  label: "Step Number",
                  name: "number",
                  widget: "number",
                  value_type: "int",
                }
              - { label: "Title", name: "title", widget: "string" }
              - { label: "Description", name: "description", widget: "text" }

  # Galleries
  - name: "galleries"
    label: "Wedding Galleries"
    folder: "frontend/src/content/galleries"
    create: true
    slug: "{{slug}}"
    fields:
      - { label: "Title", name: "title", widget: "string" }
      - { label: "Image", name: "image", widget: "image" }
      - {
          label: "Display Order",
          name: "order",
          widget: "number",
          value_type: "int",
        }
      - {
          label: "Featured on Homepage",
          name: "featured",
          widget: "boolean",
          default: false,
        }

  # Testimonials
  - name: "testimonials"
    label: "Testimonials"
    folder: "frontend/src/content/testimonials"
    create: true
    slug: "{{slug}}"
    fields:
      - { label: "Quote", name: "quote", widget: "text" }
      - { label: "Author Name", name: "author", widget: "string" }
      - {
          label: "Featured on Homepage",
          name: "featured",
          widget: "boolean",
          default: false,
        }
      - {
          label: "Display Order",
          name: "order",
          widget: "number",
          value_type: "int",
        }
```

### Success Criteria:

#### Automated Verification:

- [x] `config.yml` is valid YAML (no syntax errors)
- [x] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:

- [ ] Navigate to `/admin/`
- [ ] All collections appear in sidebar
- [ ] Can click into each collection and see fields
- [ ] Image upload widget works (select/preview images)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that the CMS dashboard shows all collections correctly before proceeding to the next phase.

---

## Phase 4: Refactor Pages to Use Content Collections

### Overview

Update all Astro pages to read content from collections instead of hardcoded values.

### Changes Required:

#### 1. Update Homepage

**File**: `frontend/src/pages/index.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import { getEntry, getCollection } from 'astro:content';

// Load content from collections
const siteSettings = await getEntry('site-settings', 'home');
const processSteps = await getEntry('process-steps', 'main');

// Get featured galleries (for "Recent Weddings" section)
const allGalleries = await getCollection('galleries');
const featuredGalleries = allGalleries
  .filter(g => g.data.featured)
  .sort((a, b) => a.data.order - b.data.order)
  .slice(0, 3);

// Get featured testimonial
const allTestimonials = await getCollection('testimonials');
const featuredTestimonial = allTestimonials
  .filter(t => t.data.featured)
  .sort((a, b) => a.data.order - b.data.order)[0];

// Load about content for the "Hey I'm Katelynn" section
const aboutContent = await getEntry('about', 'main');

const { hero, outdoorSection, ctaSection } = siteSettings.data;
const { steps } = processSteps.data;
---

<Layout title="Home" description="Professional photography capturing life's beautiful moments. Specializing in weddings, portraits, and events.">
  <!-- Hero Section -->
  <section class="relative h-screen flex items-center justify-center">
    <div class="absolute inset-0 z-0">
      <img
        src={hero.backgroundImage}
        alt=""
        class="w-full h-full object-cover"
        loading="eager"
      />
      <div class="absolute inset-0 bg-black/40"></div>
    </div>

    <div class="relative z-10 text-center text-white px-4 max-w-4xl">
      <h1 class="text-4xl md:text-6xl lg:text-7xl font-serif mb-6" set:html={hero.title.replace(/\n/g, '<br />')} />
      <h2 class="text-2xl md:text-3xl lg:text-4xl font-serif mb-8 text-white/95" set:html={hero.subtitle.replace(/\n/g, '<br />')} />
    </div>

    <div class="absolute bottom-8 left-1/2 -translate-x-1/2 animate-bounce">
      <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
      </svg>
    </div>
  </section>

  <!-- Outdoor Wedding Section -->
  <section class="py-20 bg-white">
    <div class="container mx-auto px-4">
      <div class="text-center mb-12 max-w-4xl mx-auto">
        <h2 class="text-3xl md:text-4xl font-serif text-primary-900 mb-6">
          {outdoorSection.heading}
        </h2>
        <p class="text-lg md:text-xl text-primary-700 leading-relaxed">
          {outdoorSection.body}
        </p>
        <div class="mt-8">
          <a href="/portfolio" class="btn-primary">
            {outdoorSection.buttonText}
          </a>
        </div>
      </div>
    </div>
  </section>

  <!-- About Katelynn Section -->
  <section class="py-20 bg-primary-100">
    <div class="container mx-auto px-4">
      <div class="text-center mb-12">
        <h2 class="text-3xl md:text-4xl font-serif text-primary-900 mb-4">HEY, I'M KATELYNN!</h2>
      </div>
      <div class="max-w-4xl mx-auto">
        {aboutContent.data.paragraphs.map((paragraph: string) => (
          <p class="text-lg text-primary-700 mb-6 leading-relaxed">
            {paragraph}
          </p>
        ))}
        <div class="text-center">
          <a href="/contact" class="btn-primary">
            LET'S CHAT!
          </a>
        </div>
      </div>
    </div>
  </section>

  <!-- Here's How It Works Section -->
  <section class="py-20 bg-white">
    <div class="container mx-auto px-4">
      <div class="text-center mb-12">
        <h2 class="text-3xl md:text-4xl font-serif text-primary-900 mb-4">HERE'S HOW IT WORKS</h2>
        <h3 class="text-xl md:text-2xl text-primary-700">LET'S BREAK IT DOWN STEP BY STEP</h3>
      </div>
      <div class="max-w-5xl mx-auto">
        <div class="grid grid-cols-1 md:grid-cols-5 gap-8">
          {steps.map((step: { number: number; title: string; description: string }) => (
            <div class="text-center">
              <div class="text-4xl font-serif text-accent mb-4">{step.number}</div>
              <h4 class="font-serif text-lg text-primary-900 mb-2">{step.title}</h4>
              <p class="text-sm text-primary-700">{step.description}</p>
            </div>
          ))}
        </div>
      </div>
      <div class="text-center mt-12">
        <a href="/contact" class="btn-primary">
          LET'S GET STARTED!
        </a>
      </div>
    </div>
  </section>

  <!-- Recent Weddings Section -->
  <section class="py-20 bg-primary-100">
    <div class="container mx-auto px-4">
      <div class="text-center mb-12">
        <h2 class="text-3xl md:text-4xl font-serif text-primary-900 mb-4">TAKE A LOOK AT</h2>
        <h2 class="text-3xl md:text-4xl font-serif text-primary-900">MY RECENT WEDDINGS</h2>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-6xl mx-auto">
        {featuredGalleries.map((gallery) => (
          <div class="group relative overflow-hidden rounded-sm aspect-[4/3]">
            <img
              src={gallery.data.image}
              alt={gallery.data.title}
              class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
              loading="lazy"
            />
            <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent"></div>
            <div class="absolute bottom-0 left-0 right-0 p-6 text-white">
              <h3 class="text-2xl font-serif mb-2">{gallery.data.title}</h3>
            </div>
          </div>
        ))}
      </div>
      <div class="text-center mt-12">
        <a href="/portfolio" class="btn-secondary">
          VIEW MORE
        </a>
      </div>
    </div>
  </section>

  <!-- Testimonials Section -->
  {featuredTestimonial && (
    <section class="py-20 bg-white">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-3xl md:text-4xl font-serif text-primary-900 mb-4">KIND WORDS FROM LOVELY COUPLES</h2>
        </div>
        <div class="max-w-4xl mx-auto">
          <div class="bg-primary-50 p-8 md:p-12 rounded-sm">
            <p class="text-lg text-primary-700 mb-8 leading-relaxed italic">
              "{featuredTestimonial.data.quote}"
            </p>
            <p class="text-lg font-serif text-primary-900">{featuredTestimonial.data.author}</p>
          </div>
        </div>
      </div>
    </section>
  )}

  <!-- CTA Section -->
  <section class="py-20 bg-primary-900 text-white text-center">
    <div class="container mx-auto px-4 max-w-3xl">
      <h2 class="text-3xl md:text-4xl font-serif mb-6">
        {ctaSection.heading}
      </h2>
      <a href="/contact" class="btn-primary bg-accent hover:bg-accent-dark">
        {ctaSection.buttonText}
      </a>
    </div>
  </section>
</Layout>
```

#### 2. Update About Page

**File**: `frontend/src/pages/about.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import { getEntry } from 'astro:content';

const aboutContent = await getEntry('about', 'main');
const { pageTitle, photo, paragraphs } = aboutContent.data;
---

<Layout title="About" description="Learn more about Katelynn, a professional photographer specializing in weddings, portraits, and events.">
  <!-- Page Header -->
  <section class="pt-32 pb-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h1 class="text-4xl md:text-5xl font-serif text-primary-900 mb-4">{pageTitle}</h1>
    </div>
  </section>

  <!-- Main Content -->
  <section class="py-16">
    <div class="container mx-auto px-4">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-12 items-start max-w-6xl mx-auto">
        <!-- Image -->
        <div>
          <img
            src={photo}
            alt="Katelynn with camera"
            class="w-full rounded-sm shadow-lg"
          />
        </div>

        <!-- Content -->
        <div class="space-y-6">
          <h2 class="text-3xl font-serif text-primary-900">HEY, I'M KATELYNN!</h2>

          {paragraphs.map((paragraph: string) => (
            <p class="text-lg text-primary-700 leading-relaxed">
              {paragraph}
            </p>
          ))}

          <div class="pt-6">
            <a href="/contact" class="btn-primary">
              LET'S CHAT!
            </a>
          </div>
        </div>
      </div>
    </div>
  </section>
</Layout>
```

#### 3. Update Pricing Page

**File**: `frontend/src/pages/pricing.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import { getEntry } from 'astro:content';

const pricingContent = await getEntry('pricing', 'main');
const { pageTitle, pageIntro, packagesHeading, packagesDescription, ctaHeading, ctaButtonText } = pricingContent.data;
---

<Layout title="Pricing" description="Wedding photography packages and pricing information. Contact me to discuss custom packages tailored to your needs.">
  <!-- Page Header -->
  <section class="pt-32 pb-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h1 class="text-4xl md:text-5xl font-serif text-primary-900 mb-4">{pageTitle}</h1>
      <p class="text-primary-600 max-w-2xl mx-auto">
        {pageIntro}
      </p>
    </div>
  </section>

  <!-- Pricing Section -->
  <section class="py-16">
    <div class="container mx-auto px-4">
      <div class="max-w-4xl mx-auto">
        <div class="bg-primary-50 p-8 md:p-12 rounded-sm mb-8">
          <h2 class="text-2xl font-serif text-primary-900 mb-6">{packagesHeading}</h2>
          {packagesDescription.map((paragraph: string) => (
            <p class="text-lg text-primary-700 mb-6 leading-relaxed">
              {paragraph}
            </p>
          ))}
          <div class="text-center">
            <a href="/contact" class="btn-primary">
              Get Started
            </a>
          </div>
        </div>

        <div class="text-center mb-8">
          <h3 class="text-xl font-serif text-primary-900 mb-4">{ctaHeading}</h3>
        </div>

        <div class="text-center">
          <a href="/contact" class="btn-primary text-lg px-8 py-4">
            {ctaButtonText}
          </a>
        </div>
      </div>
    </div>
  </section>
</Layout>
```

#### 4. Update Portfolio Page

**File**: `frontend/src/pages/portfolio.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import { getCollection } from 'astro:content';

const allGalleries = await getCollection('galleries');
const sortedGalleries = allGalleries.sort((a, b) => a.data.order - b.data.order);
---

<Layout title="Galleries" description="Browse wedding galleries from beautiful outdoor venues in Columbus and throughout Ohio.">
  <!-- Page Header -->
  <section class="pt-32 pb-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h1 class="text-4xl md:text-5xl font-serif text-primary-900 mb-4">Galleries</h1>
    </div>
  </section>

  <!-- Gallery Grid Section -->
  <section class="py-16">
    <div class="container mx-auto px-4">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 max-w-6xl mx-auto">
        {sortedGalleries.map((gallery) => (
          <a
            href="#"
            class="group relative overflow-hidden rounded-sm aspect-[4/3]"
          >
            <img
              src={gallery.data.image}
              alt={gallery.data.title}
              class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
              loading="lazy"
            />
            <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent"></div>
            <div class="absolute bottom-0 left-0 right-0 p-6 text-white">
              <h3 class="text-xl font-serif mb-2">{gallery.data.title}</h3>
            </div>
          </a>
        ))}
      </div>
    </div>
  </section>
</Layout>
```

#### 5. Update Contact Page

**File**: `frontend/src/pages/contact.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
import ContactForm from '../components/ContactForm.astro';
import { getEntry } from 'astro:content';

const contactContent = await getEntry('contact', 'main');
const { pageTitle, pageIntro, email, location, responseTime, bookingInfo } = contactContent.data;

// API Gateway URL - update with actual endpoint
const apiUrl = 'https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com';
---

<Layout title="Inquire" description="Get in touch to discuss your photography needs. I'd love to hear about your upcoming wedding, portrait session, or event.">
  <!-- Page Header -->
  <section class="pt-32 pb-16 bg-primary-100">
    <div class="container mx-auto px-4 text-center">
      <h1 class="text-4xl md:text-5xl font-serif text-primary-900 mb-4">{pageTitle}</h1>
      <p class="text-primary-600 max-w-2xl mx-auto">
        {pageIntro}
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
                <a href={`mailto:${email}`} class="hover:text-accent transition-colors">
                  {email}
                </a>
              </li>
              <li class="flex items-start">
                <svg class="w-5 h-5 text-accent mr-3 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
                <span>{location}</span>
              </li>
            </ul>
          </div>

          <div>
            <h3 class="font-serif text-xl text-primary-900 mb-4">Response Time</h3>
            <p class="text-primary-700 text-sm">
              {responseTime}
            </p>
          </div>

          <div>
            <h3 class="font-serif text-xl text-primary-900 mb-4">Booking Info</h3>
            <p class="text-primary-700 text-sm">
              {bookingInfo}
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

- [x] TypeScript compiles: `cd frontend && npx astro check` (pre-existing errors in other components)
- [x] Build succeeds: `cd frontend && npm run build`
- [x] No console errors during build

#### Manual Verification:

- [ ] All pages render correctly with content from collections
- [ ] Homepage shows hero, about section, process steps, recent weddings, testimonial
- [ ] About page shows bio and photo
- [ ] Pricing page shows all content
- [ ] Portfolio page shows all galleries
- [ ] Contact page shows all info

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that all pages render correctly before proceeding to the next phase.

---

## Phase 5: End-to-End Testing

### Overview

Verify the complete flow: admin edits content in CMS, changes commit to git, site rebuilds with new content.

### Manual Testing Steps:

1. **Test CMS Login**
   - [ ] Navigate to `https://[site-url]/admin/`
   - [ ] Log in via DecapBridge
   - [ ] Verify dashboard loads with all collections

2. **Test Text Edit**
   - [ ] Go to "About Page" > "About Content"
   - [ ] Change one paragraph
   - [ ] Click "Save" / "Publish"
   - [ ] Verify git commit appears in repository
   - [ ] Wait for Amplify rebuild
   - [ ] Verify change appears on live site

3. **Test Image Upload**
   - [ ] Go to "Wedding Galleries"
   - [ ] Click "New" to add a gallery
   - [ ] Upload a new image
   - [ ] Fill in title, order, featured flag
   - [ ] Save and publish
   - [ ] Verify image appears on portfolio page after rebuild

4. **Test Multiple Edits**
   - [ ] Edit homepage hero text
   - [ ] Edit a testimonial
   - [ ] Edit pricing description
   - [ ] Publish all changes
   - [ ] Verify all changes appear after rebuild

### Success Criteria:

#### Manual Verification:

- [ ] Admin can log in and see all collections
- [ ] Text edits save and appear on site after rebuild
- [ ] Image uploads work and display correctly
- [ ] Amplify auto-deploys on git commits
- [ ] Both admin users can log in and make edits

---

## Testing Strategy

### Integration Tests:

- Build succeeds with content collections
- All pages render with content from collections
- No TypeScript errors

### Manual Testing Steps:

1. Log in to CMS at `/admin/`
2. Edit text content in each collection
3. Upload a new image
4. Verify changes appear on live site after Amplify rebuild

## Performance Considerations

- **Build Time**: Adding content collections adds minimal build time (reading JSON/YAML files)
- **No Runtime Cost**: Site remains fully static, no database queries
- **Image Optimization**: Consider adding Astro's Image component for optimized images in future

## Migration Notes

- Content is migrated from hardcoded `.astro` files to JSON/YAML files
- Original pages are replaced with collection-reading versions
- No database migration needed (git-based content)
- Rollback: revert git commits to restore original hardcoded pages

## References

- Astro Content Collections: https://docs.astro.build/en/guides/content-collections/
- Decap CMS + Astro: https://docs.astro.build/en/guides/cms/decap-cms/
- DecapBridge: https://decapbridge.com/
- DecapBridge Docs: https://decapbridge.com/docs/introduction
