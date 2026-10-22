import { redirect } from "next/navigation";

/** v2 became the home page. */
export default function V2() {
  redirect("/");
}
