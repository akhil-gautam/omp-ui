import { IconMoon, IconPanel, IconSun } from "./Icons";

type Props = {
	theme: "dark" | "light";
	onToggleTheme: () => void;
	onToggleSidebar: () => void;
	sidebarOpen: boolean;
};

/** The narrow strip on the far left. */
export default function IconRail({ theme, onToggleTheme, onToggleSidebar, sidebarOpen }: Props) {
	return (
		<nav className="rail" aria-label="Application">
			<button
				className="rail-button"
				onClick={onToggleSidebar}
				title={sidebarOpen ? "Hide the sidebar" : "Show the sidebar"}
				aria-label={sidebarOpen ? "Hide the sidebar" : "Show the sidebar"}
			>
				<IconPanel />
			</button>
			<div className="rail-spacer" />
			<button
				className="rail-button"
				onClick={onToggleTheme}
				title={theme === "dark" ? "Switch to the light theme" : "Switch to the dark theme"}
				aria-label="Toggle the theme"
			>
				{theme === "dark" ? <IconSun /> : <IconMoon />}
			</button>
		</nav>
	);
}
