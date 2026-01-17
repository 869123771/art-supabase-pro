# Art Supabase Pro

## Project Overview

Art Supabase Pro is an art project management system built on Supabase, designed to provide artists, galleries, and art institutions with a comprehensive digital solution. This project integrates modern web technologies, leveraging Supabase as the backend service to deliver data storage, user authentication, real-time subscriptions, and more.

## Key Features

- **User Authentication System**: Supports email/password login and social account login
- **Artwork Management**: Full CRUD operations for artworks, with support for categories and tags
- **Portfolio Display**: Professional online portfolio presentation functionality
- **Comment and Interaction System**: Users can comment on and rate artworks
- **Real-time Data Synchronization**: Utilizes Supabase Realtime for live data updates
- **Responsive Design**: Perfectly adapted for both desktop and mobile devices

## Technology Stack

- **Frontend Framework**: Vue.js / React / Other modern frontend frameworks
- **Backend-as-a-Service**: Supabase
- **Database**: PostgreSQL
- **Authentication**: Supabase Auth
- **Storage**: Supabase Storage (for storing artwork images)
- **Real-time Subscriptions**: Supabase Realtime

## Quick Start

### Prerequisites

- Node.js 16.x or higher
- npm or yarn package manager
- Supabase account (free registration available)

### Installation Steps

1. **Clone the Project**

```bash
git clone https://gitee.com/wangyanghub/art-supbase-pro.git
cd art-supbase-pro
```

2. **Install Dependencies**

```bash
npm install
# or
yarn install
```

3. **Configure Environment Variables**

Create a `.env.local` file and add the following configurations:

```env
VITE_SUPABASE_URL=your-supabase-project-url
VITE_SUPABASE_ANON_KEY=your-supabase-anon-key
```

4. **Start the Development Server**

```bash
npm run dev
# or
yarn dev
```

### Supabase Project Setup

1. Create a new project on [Supabase](https://supabase.com)
2. Create required database tables:
   - `profiles` - User profile table
   - `artworks` - Artwork table
   - `categories` - Artwork category table
   - `comments` - Comment table
3. Configure Row Level Security (RLS) policies
4. Enable Storage Bucket for image storage

## Project Structure

```
art-supbase-pro/
├── src/
│   ├── components/      # Reusable components
│   ├── views/           # Page views
│   ├── stores/          # State management
│   ├── composables/     # Composable functions
│   ├── utils/           # Utility functions
│   ├── assets/          # Static assets
│   └── App.vue          # Root component
├── public/              # Public assets
├── .env.local           # Environment variable configuration
├── package.json         # Project dependency configuration
└── README.md            # Project documentation
```

## Core Function Usage

### User Registration and Login

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(URL, ANON_KEY)

// Register
const { data, error } = await supabase.auth.signUp({
  email: 'user@example.com',
  password: 'password123'
})
```

### Uploading Artworks

```javascript
// Upload image
const { data, error } = await supabase.storage
  .from('artworks')
  .upload('path/to/image.jpg', file)

// Save artwork details
const { data, error } = await supabase
  .from('artworks')
  .insert([
    {
      title: 'Artwork Title',
      description: 'Artwork Description',
      image_url: imageUrl,
      artist_id: userId
    }
  ])
```

### Real-time Data Subscription

```javascript
// Subscribe to artwork data changes
supabase
  .channel('public:artworks')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'artworks' }, 
    (payload) => {
      console.log('Artwork data updated:', payload)
    }
  )
  .subscribe()
```

## API Reference

For the complete Supabase JavaScript client API, refer to the [official documentation](https://supabase.com/docs/reference/javascript/installing).

## Deployment

### Build Production Version

```bash
npm run build
# or
yarn build
```

### Deploy to Vercel

```bash
npm i -g vercel
vercel
```

### Deploy to Netlify

```bash
npm run build
netlify deploy --prod --dir=dist
```

## Contribution Guidelines

1. Fork this project
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Create a Pull Request

## License

This project is open-sourced under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

- Project URL: https://gitee.com/wangyanghub/art-supbase-pro
- Author: [wangyanghub]
- Email: [author@example.com]

## Acknowledgments

- [Supabase](https://supabase.com/) - Open-source Firebase alternative
- [Vue.js](https://vuejs.org/) - Progressive JavaScript framework
- [Gitee](https://gitee.com/) - Code hosting platform

---

For any questions or suggestions, feel free to open an Issue or Pull Request on Gitee.