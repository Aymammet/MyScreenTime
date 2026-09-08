export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-5xl items-center px-6 py-16">
      <section className="w-full rounded-3xl bg-white p-8 shadow-sm sm:p-12">
        <p className="mb-3 text-sm font-semibold tracking-widest text-indigo-600 uppercase">
          Family screen-time tracker
        </p>
        <h1 className="max-w-2xl text-4xl font-bold tracking-tight sm:text-6xl">
          MyScreenTime
        </h1>
        <p className="mt-5 max-w-2xl text-lg leading-8 text-slate-600">
          Help your family build healthier screen habits with clear daily
          limits, device tracking, and useful insights.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <span className="rounded-full bg-indigo-50 px-4 py-2 text-sm font-medium text-indigo-700">
            Project foundation ready
          </span>
          <span className="rounded-full bg-slate-100 px-4 py-2 text-sm font-medium text-slate-700">
            MVP implementation next
          </span>
        </div>
      </section>
    </main>
  );
}
