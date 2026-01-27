# Wix Content Export Plan

## Overview

This plan covers extracting text content, page structure, and key images from the existing Wix website to populate the new Astro site. The focus is on **content** (text, bios, descriptions) rather than bulk photo migration.

## Current State Analysis

### Astro Templates with Placeholder Content

The following files contain placeholder text that needs real content:

| File                                        | Placeholders to Replace                            |
| ------------------------------------------- | -------------------------------------------------- |
| `astro-portfolio/src/pages/index.astro`     | Hero tagline, about teaser, `[X] years` experience |
| `astro-portfolio/src/pages/about.astro`     | Full bio, photography philosophy, approach bullets |
| `astro-portfolio/src/pages/contact.astro`   | Email address, `[Your Location]`, booking info     |
| `astro-portfolio/src/pages/portfolio.astro` | Gallery image paths and descriptions               |

### Images Needed

| Image               | Purpose                 | Astro Path                      |
| ------------------- | ----------------------- | ------------------------------- |
| Hero background     | Home page hero section  | `/images/hero-bg.jpg`           |
| About teaser        | Home page about preview | `/images/about-teaser.jpg`      |
| About full          | About page main photo   | `/images/about-full.jpg`        |
| Wedding featured    | Home category card      | `/images/wedding-featured.jpg`  |
| Portrait featured   | Home category card      | `/images/portrait-featured.jpg` |
| Event featured      | Home category card      | `/images/event-featured.jpg`    |
| Gallery images (9+) | Portfolio page          | `/images/gallery/*.jpg`         |

## Desired End State

After completing this plan:

1. All placeholder text replaced with real content from Wix
2. Key feature images downloaded and placed in correct directories
3. Astro site ready to deploy with personalized content
4. Screenshots of Wix site saved for reference

### Verification

- All `[X]` and `[Your Location]` placeholders removed
- About page has real bio text
- Contact page has real email and location
- Portfolio has real gallery images
- Site builds successfully with `npm run build`

## What We're NOT Doing

- Bulk downloading 100GB+ of photos (handled separately by upload scripts)
- Migrating client album data (already have scripts for this)
- Preserving Wix URL structure
- Migrating Wix forms (already rebuilt with Lambda)

---

## Implementation Approach

Two options depending on tooling preference:

### Option A: Puppeteer MCP Server (Automated)

Use browser automation to navigate Wix site, take screenshots, and extract content programmatically.

### Option B: Manual Export (No Setup Required)

Manually copy/paste content and download images from Wix.

---

## Option A: Puppeteer MCP Server Setup

### Phase A.1: Install Puppeteer MCP Server

#### 1. Install the MCP Server

```bash
npm install -g @anthropic/mcp-server-puppeteer
```

#### 2. Configure MCP Server

**File**: `~/.claude/mcp.json` (or project `.mcp.json`)

Add to existing configuration:

```json
{
  "mcpServers": {
    "puppeteer": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-puppeteer"]
    }
  }
}
```

#### 3. Restart Claude Code

```bash
# Exit and restart Claude Code to load new MCP server
claude
```

#### 4. Verify Installation

After restart, the following tools should be available:

- `puppeteer_navigate` - Navigate to URLs
- `puppeteer_screenshot` - Capture screenshots
- `puppeteer_click` - Click elements
- `puppeteer_fill` - Fill form fields
- `puppeteer_evaluate` - Run JavaScript to extract content

### Success Criteria:

#### Automated Verification:

- [ ] `npm list -g @anthropic/mcp-server-puppeteer` shows package installed
- [ ] MCP server appears in Claude Code tool list after restart

#### Manual Verification:

- [ ] Can navigate to a test URL using puppeteer_navigate
- [ ] Can take a screenshot using puppeteer_screenshot

---

### Phase A.2: Capture Wix Site Content

#### 1. Navigate and Screenshot Each Page

Using Puppeteer MCP tools, capture each page:

```
Pages to capture:
1. Homepage - https://[wix-site-url]/
2. About page - https://[wix-site-url]/about
3. Portfolio/Gallery - https://[wix-site-url]/portfolio (or /gallery)
4. Contact page - https://[wix-site-url]/contact
```

Save screenshots to:

```bash
mkdir -p ~/wix-export/screenshots
# Screenshots saved as:
# ~/wix-export/screenshots/home.png
# ~/wix-export/screenshots/about.png
# ~/wix-export/screenshots/portfolio.png
# ~/wix-export/screenshots/contact.png
```

#### 2. Extract Text Content

Use `puppeteer_evaluate` to extract text from each page:

```javascript
// Example: Extract about page content
document.querySelector(".about-section")?.innerText;
```

Save extracted content to:

```bash
mkdir -p ~/wix-export/content
# Content saved as:
# ~/wix-export/content/about.txt
# ~/wix-export/content/home.txt
# ~/wix-export/content/contact.txt
```

#### 3. Identify and Download Key Images

From screenshots/inspection, identify:

- Hero background image URL
- About page photo URL
- Featured category images
- Best portfolio images for gallery

Download using browser or curl:

```bash
mkdir -p ~/wix-export/images
curl -o ~/wix-export/images/hero-bg.jpg "[wix-image-url]"
```

### Success Criteria:

#### Automated Verification:

- [ ] Screenshots exist for all pages in `~/wix-export/screenshots/`
- [ ] Text content extracted to `~/wix-export/content/`

#### Manual Verification:

- [ ] Screenshots capture full page content
- [ ] Extracted text is readable and complete
- [ ] Key images identified and downloaded

---

## Option B: Manual Export (No Setup)

### Phase B.1: Screenshot and Copy Content

#### 1. Take Screenshots Manually

Open each Wix page in browser and use browser screenshot tools:

**Chrome/Edge:**

- Press F12 (DevTools)
- Ctrl+Shift+P → "Capture full size screenshot"

**Firefox:**

- Right-click → "Take Screenshot" → "Save full page"

Save to:

```bash
mkdir -p ~/wix-export/screenshots
```

#### 2. Copy Text Content

For each page, select and copy text:

**Homepage:**

- Hero headline and subtext
- About teaser paragraph
- Any testimonials or taglines

**About Page:**

- Full bio text
- Photography philosophy
- Approach/values bullets
- Years of experience

**Contact Page:**

- Email address
- Physical location/service area
- Business hours (if listed)
- Booking lead time info

Save to text files:

```bash
mkdir -p ~/wix-export/content

# Create content files
cat > ~/wix-export/content/about.txt << 'EOF'
[Paste about page content here]
EOF

cat > ~/wix-export/content/home.txt << 'EOF'
[Paste home page content here]
EOF

cat > ~/wix-export/content/contact.txt << 'EOF'
[Paste contact info here]
EOF
```

#### 3. Download Key Images

**From Wix Media Manager:**

1. Log into Wix Dashboard
2. Go to Media Manager
3. Download these specific images:
   - Hero/banner image
   - Profile/about photo
   - 3 featured category images (wedding, portrait, event)
   - 9-12 best portfolio images

**Alternative - From Live Site:**

1. Right-click image → "Open image in new tab"
2. Save image to `~/wix-export/images/`

```bash
mkdir -p ~/wix-export/images/gallery
# Save images with descriptive names:
# ~/wix-export/images/hero-bg.jpg
# ~/wix-export/images/about-full.jpg
# ~/wix-export/images/wedding-featured.jpg
# ~/wix-export/images/portrait-featured.jpg
# ~/wix-export/images/event-featured.jpg
# ~/wix-export/images/gallery/wedding-1.jpg
# etc.
```

### Success Criteria:

#### Manual Verification:

- [ ] Screenshots saved for all 4 main pages
- [ ] About bio text copied and saved
- [ ] Contact info (email, location) documented
- [ ] Hero image downloaded
- [ ] About photo downloaded
- [ ] 3 featured category images downloaded
- [ ] 9+ gallery images downloaded

---

## Phase 2: Update Astro Templates

### Overview

Replace placeholder content in Astro files with exported Wix content.

### Changes Required:

#### 1. Update Home Page

**File**: `astro-portfolio/src/pages/index.astro`

Replace placeholders:

```astro
// Line ~43-48: Update hero content
<h1 class="text-4xl md:text-6xl lg:text-7xl font-serif mb-6">
  [REPLACE: Hero headline from Wix]
</h1>
<p class="text-lg md:text-xl text-white/90 mb-8 max-w-2xl mx-auto">
  [REPLACE: Hero subtext from Wix]
</p>

// Line ~113-117: Update about teaser
<p class="text-primary-700 mb-6 leading-relaxed">
  [REPLACE: About teaser from Wix - include actual years of experience]
</p>
```

#### 2. Update About Page

**File**: `astro-portfolio/src/pages/about.astro`

Replace bio content:

```astro
// Lines ~30-42: Replace bio paragraphs
<p class="text-primary-700 leading-relaxed">
  [REPLACE: First bio paragraph from Wix]
</p>

<p class="text-primary-700 leading-relaxed">
  [REPLACE: Second bio paragraph from Wix]
</p>

// Lines ~46-63: Update approach bullets if different
```

#### 3. Update Contact Page

**File**: `astro-portfolio/src/pages/contact.astro`

Replace contact info:

```astro
// Line ~39: Update email
<a href="mailto:[REAL-EMAIL]" class="hover:text-accent transition-colors">
  [REAL-EMAIL]
</a>

// Line ~48: Update location
<span>[REAL LOCATION - e.g., "Portland, Oregon"]</span>
```

#### 4. Update Portfolio Gallery

**File**: `astro-portfolio/src/pages/portfolio.astro`

Update gallery images array:

```astro
const galleryImages = [
  { src: '/images/gallery/wedding-1.jpg', alt: '[Real description]', category: 'wedding' },
  { src: '/images/gallery/wedding-2.jpg', alt: '[Real description]', category: 'wedding' },
  // ... update all entries with real descriptions
];
```

#### 5. Copy Images to Astro Public Directory

```bash
# Copy exported images to Astro public folder
cp ~/wix-export/images/hero-bg.jpg astro-portfolio/public/images/
cp ~/wix-export/images/about-full.jpg astro-portfolio/public/images/
cp ~/wix-export/images/about-teaser.jpg astro-portfolio/public/images/
cp ~/wix-export/images/wedding-featured.jpg astro-portfolio/public/images/
cp ~/wix-export/images/portrait-featured.jpg astro-portfolio/public/images/
cp ~/wix-export/images/event-featured.jpg astro-portfolio/public/images/
cp ~/wix-export/images/gallery/*.jpg astro-portfolio/public/images/gallery/
```

### Success Criteria:

#### Automated Verification:

- [ ] `cd astro-portfolio && npm run build` succeeds
- [ ] No `[X]` or `[Your Location]` placeholders remain: `grep -r "\[X\]\|\[Your" src/`

#### Manual Verification:

- [ ] `npm run dev` shows site with real content
- [ ] About page displays actual bio
- [ ] Contact page shows real email and location
- [ ] All images load correctly
- [ ] Portfolio gallery shows real photos

---

## Phase 3: Deploy Updated Site

### Overview

Build and deploy the updated Astro site to S3.

### Changes Required:

#### 1. Build Site

```bash
cd ~/repos/katelynns-photography/astro-portfolio
npm run build
```

#### 2. Deploy to S3

```bash
cd ~/repos/katelynns-photography
./scripts/deploy_astro.sh
```

### Success Criteria:

#### Automated Verification:

- [ ] Build completes without errors
- [ ] `aws s3 ls s3://katelynns-photography-website/ --profile jw-dev` shows updated files

#### Manual Verification:

- [ ] Site accessible via S3 URL or CloudFront (when available)
- [ ] All pages display correctly with real content
- [ ] Images load properly
- [ ] No broken links

---

## Content Checklist

Use this checklist to track content extraction:

### Text Content

- [ ] Hero headline
- [ ] Hero subtext
- [ ] About teaser (for home page)
- [ ] Full bio (paragraph 1)
- [ ] Full bio (paragraph 2)
- [ ] Photography approach/philosophy
- [ ] Years of experience number
- [ ] Email address
- [ ] Location/service area
- [ ] Booking lead time info

### Images

- [ ] Hero background (`hero-bg.jpg`)
- [ ] About teaser (`about-teaser.jpg`)
- [ ] About full (`about-full.jpg`)
- [ ] Wedding featured (`wedding-featured.jpg`)
- [ ] Portrait featured (`portrait-featured.jpg`)
- [ ] Event featured (`event-featured.jpg`)
- [ ] Gallery image 1
- [ ] Gallery image 2
- [ ] Gallery image 3
- [ ] Gallery image 4
- [ ] Gallery image 5
- [ ] Gallery image 6
- [ ] Gallery image 7
- [ ] Gallery image 8
- [ ] Gallery image 9

---

## References

- Phase 4 Migration Plan: `thoughts/shared/plans/2026-01-08-phase4-migration.md`
- Puppeteer MCP Server: https://github.com/anthropics/mcp-server-puppeteer
- Astro Documentation: https://docs.astro.build
- Wix Media Download: https://support.wix.com/en/article/wix-media-downloading-files-from-the-media-manager

---

## Summary

This plan provides two paths for extracting content from Wix:

**Option A (Puppeteer MCP):**

- Automated browser navigation and screenshots
- Programmatic content extraction
- Best for: Reproducible process, multiple pages

**Option B (Manual):**

- Browser screenshots and copy/paste
- Direct image downloads from Wix
- Best for: Quick one-time export, no setup required

**Estimated Time:**

- Option A Setup: 15-30 minutes
- Option A Extraction: 30-45 minutes
- Option B Manual: 45-60 minutes
- Template Updates: 30-45 minutes
- Deployment: 10 minutes

**Total: 1-2 hours**
