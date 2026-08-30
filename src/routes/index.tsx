import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "IOMMS - Multi-Tenant Memo Management System" },
      {
        name: "description",
        content:
          "IOMMS is a multi-tenant inter-office memo management system for organizations, departments, approvals and document workflows.",
      },
      { property: "og:title", content: "IOMMS - Memo Management System" },
      {
        property: "og:description",
        content:
          "Manage inter-office memos, departments and approvals across multiple organizations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

function Index() {
  return (
    <>
      <h1 className="sr-only">IOMMS - Multi-Tenant Memo Management System</h1>
      <iframe
        src="/app/index.html"
        title="IOMMS Memo Management System"
        className="fixed inset-0 h-full w-full border-0"
      />
    </>
  );
}
