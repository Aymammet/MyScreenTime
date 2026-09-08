# MyScreenTime

MyScreenTime is a responsive web application that helps parents track and manage children's daily screen time across multiple devices.

## Technology

- Next.js and React
- TypeScript
- Tailwind CSS
- PostgreSQL and Prisma
- Zod validation
- Vitest, Testing Library, and Playwright

Product decisions and MVP boundaries are documented in [docs/product-decisions.md](docs/product-decisions.md). Project progress is tracked in [plan.md](plan.md).

## Local setup

### Requirements

- Node.js 22 or newer
- npm
- PostgreSQL

### Installation

1. Install dependencies:

   ```bash
   npm install
   ```

2. Copy the environment template and replace its placeholders:

   ```bash
   cp .env.example .env
   ```

3. Generate the Prisma client and apply migrations:

   ```bash
   npm run db:generate
   npx prisma migrate deploy
   ```

4. Start the development server:

   ```bash
   npm run dev
   ```

Open [http://localhost:3000](http://localhost:3000).

## Development commands

| Command               | Purpose                               |
| --------------------- | ------------------------------------- |
| `npm run dev`         | Start the development server          |
| `npm run build`       | Create a production build             |
| `npm run lint`        | Run ESLint                            |
| `npm run format`      | Format project files                  |
| `npm run typegen`     | Generate Next.js route types          |
| `npm run typecheck`   | Check TypeScript types                |
| `npm run test`        | Run unit and component tests          |
| `npm run test:e2e`    | Run browser-based tests               |
| `npm run db:generate` | Generate the Prisma client            |
| `npm run db:validate` | Validate the Prisma schema            |
| `npm run check`       | Run the main local verification suite |

## Folder structure

```text
src/app/                Next.js routes and layouts
src/components/         Reusable interface components
src/features/           Feature-specific application code
src/lib/                Shared utilities and infrastructure
prisma/                 Database schema and migrations
tests/e2e/              End-to-end tests
docs/                   Product and design documentation
```

## Coding conventions

- Use TypeScript strict mode and the `@/` import alias for `src/`.
- Keep route files in `src/app` and reusable UI in `src/components`.
- Keep domain-specific code grouped under `src/features`.
- Validate external input with Zod at application boundaries.
- Add tests for time calculations, authorization rules, and reporting logic.
- Never commit `.env` files or secrets.
