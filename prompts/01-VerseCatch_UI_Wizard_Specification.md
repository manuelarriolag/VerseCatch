# VerseCatch UI/UX Redesign Specification (Wizard)

## Objective

Redesign only the UI and navigation flow while **reusing the existing
business logic** (OCR with ML Kit, reference detection, history, Bible
retrieval, parsing, etc.).

## Wizard Flow

1.  Choose source
2.  Acquire content
3.  Review recognized text
4.  Detect references
5.  Explore references
6.  Save / Share

## Screens

### 1. Choose source

-   Paste/write text
-   Open text file
-   Choose image
-   Take photo
-   History

### 2. Acquire content

Depends on source: - Text editor - File picker - Image preview - Camera
preview with optional OCR enhancement filters

### 3. Review text

-   Editable text
-   Character counter
-   Continue button

### 4. Detect references

-   Progress state
-   Summary of detected references
-   Group duplicate references

### 5. Explore references

-   Reference chips/list
-   Bible version selector
-   Swipe between references
-   Copy verse

### 6. Finish

-   Save to history
-   Export
-   Share
-   New scan

## Components

-   Stepper
-   Primary CTA
-   Cards
-   Reference chips
-   Bible version selector
-   Progress indicator
-   Toasts/snackbars

## Technical Constraints

Reuse existing: - OCR - Parsing - History - Verse retrieval - Storage -
Business logic

Replace only: - Navigation - Layout - Visual components - Interaction
flow

## Desktop

Two-panel adaptive wizard with left stepper and right content.
