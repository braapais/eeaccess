from manim import *
import numpy as np

# --- STYLE GUIDE ---
BG_COLOR = "#F5F5F7"  # Soft Gray/White
PRIMARY_BLUE = "#007AFF" # Apple Blue
TEXT_COLOR = "#1D1D1F"  # Deep Charcoal
ACCENT_WHITE = "#FFFFFF"
MONO = "Menlo"

class EEAccess_Preview(Scene):
    def construct(self):
        self.camera.background_color = BG_COLOR

        # --- SCENE 1: HERO INTRO (0-4s) ---
        watch_body = RoundedRectangle(corner_radius=0.4, height=3, width=2.5, color=TEXT_COLOR, fill_opacity=1)
        screen = RoundedRectangle(corner_radius=0.3, height=2.7, width=2.2, color=TEXT_COLOR, fill_opacity=0)
        watch = VGroup(watch_body, screen).center()

        card1 = RoundedRectangle(corner_radius=0.1, height=0.6, width=1.8, color=PRIMARY_BLUE, fill_opacity=0.8).shift(UP*0.3)
        card2 = RoundedRectangle(corner_radius=0.1, height=0.6, width=1.8, color=TEXT_COLOR, fill_opacity=0.2).shift(ORIGIN)
        card3 = RoundedRectangle(corner_radius=0.1, height=0.6, width=1.8, color=TEXT_COLOR, fill_opacity=0.1).shift(DOWN*0.3)
        cards = VGroup(card1, card2, card3)

        headline = Text("Cards on your wrist.\nNo phone.", font=MONO, weight=BOLD, color=TEXT_COLOR, 
                        font_size=36, line_spacing=1.2).shift(DOWN*3)

        self.play(FadeIn(watch), run_time=1)
        self.play(LaggedStart(*[FadeIn(c, shift=UP*0.2) for c in cards], lag_ratio=0.2), run_time=1)
        self.play(Write(headline), run_time=1.5)
        self.wait(0.5)

        self.play(FadeOut(headline), FadeOut(cards), watch.animate.scale(1.2).set_opacity(0.5), run_time=0.8)

        # --- SCENE 2: THE RUNNER (4-9s) ---
        runner_silhouette = Circle(radius=0.5, color=TEXT_COLOR).shift(LEFT*2 + UP*1)
        runner_body = Line(runner_silhouette.get_bottom(), runner_silhouette.get_bottom() + DOWN*1, color=TEXT_COLOR)
        runner = VGroup(runner_silhouette, runner_body).shift(LEFT*3)
        
        run_text = Text("Run free.\nEnter free.", font=MONO, weight=BOLD, color=TEXT_COLOR, 
                        font_size=32).to_edge(UP, buff=1.5)

        qr_code = Square(side_length=1.5, color=TEXT_COLOR, fill_opacity=0).move_to(watch.get_center())
        qr_pattern = VGroup(*[Square(side_length=0.3, color=TEXT_COLOR, fill_opacity=1).shift(
            np.array([x*0.4, y*0.4, 0])) for x in [-1, 0, 1] for y in [-1, 0, 1]])
        qr_full = VGroup(qr_code, qr_pattern)

        self.play(FadeIn(runner), Write(run_text), run_time=1)
        self.play(ReplacementTransform(cards, qr_full), watch.animate.set_opacity(1).scale(0.83), run_time=1)
        self.wait(2)

        self.play(FadeOut(runner), FadeOut(run_text), FadeOut(qr_full), run_time=0.8)

        # --- SCENE 3: THE CYCLIST (9-14s) ---
        cyclist_silhouette = Triangle(color=TEXT_COLOR).scale(0.7).shift(RIGHT*3)
        cycle_text = Text("Ride free.\nCoffee ready.", font=MONO, weight=BOLD, color=TEXT_COLOR, 
                          font_size=32).to_edge(UP, buff=1.5)
        
        sbux_card = RoundedRectangle(corner_radius=0.1, height=0.8, width=1.6, color="#00704A", fill_opacity=1).move_to(watch.get_center())
        sbux_text = Text("STARBUCKS", font=MONO, color=WHITE, font_size=18).move_to(sbux_card.get_center())
        sbux_ui = VGroup(sbux_card, sbux_text)

        # LaTeX-free Checkmark
        check_l = Line(start=np.array([-0.3, -0.2, 0]), end=np.array([0, 0, 0]), color=PRIMARY_BLUE, stroke_width=8)
        check_r = Line(start=np.array([0, 0, 0]), end=np.array([0.4, 0.5, 0]), color=PRIMARY_BLUE, stroke_width=8)
        checkmark = VGroup(check_l, check_r).move_to(watch.get_center())

        self.play(FadeIn(cyclist_silhouette), Write(cycle_text), run_time=1)
        self.play(FadeIn(sbux_ui), run_time=0.8)
        self.play(ReplacementTransform(sbux_ui, checkmark), run_time=0.5)
        self.wait(2)

        self.play(FadeOut(cyclist_silhouette), FadeOut(cycle_text), FadeOut(checkmark), run_time=0.8)

        # --- SCENE 4: THE SHOPPER (14-19s) ---
        shopper_silhouette = Rectangle(height=2, width=1, color=TEXT_COLOR).shift(LEFT*3)
        shop_text = Text("Walk free.\nCheck out free.", font=MONO, weight=BOLD, color=TEXT_COLOR, 
                         font_size=32).to_edge(UP, buff=1.5)
        
        lidl_card = RoundedRectangle(corner_radius=0.1, height=0.8, width=1.6, color="#0050aa", fill_opacity=1).move_to(watch.get_center())
        lidl_text = Text("LIDL", font=MONO, color=WHITE, font_size=18).move_to(lidl_card.get_center())
        lidl_ui = VGroup(lidl_card, lidl_text)

        barcode = VGroup(*[Line(UP*0.3, DOWN*0.3, color=TEXT_COLOR).shift(RIGHT*i*0.1) for i in range(-5, 6)])
        barcode.move_to(watch.get_center()).scale(0.8)

        self.play(FadeIn(shopper_silhouette), Write(shop_text), run_time=1)
        self.play(FadeIn(lidl_ui), run_time=0.8)
        self.play(ReplacementTransform(lidl_ui, barcode), run_time=0.5)
        self.wait(2)

        self.play(FadeOut(shopper_silhouette), FadeOut(shop_text), FadeOut(barcode), run_time=0.8)

        # --- SCENE 5: PRIVACY & SIMPLICITY (19-23s) ---
        features = [
            "Fully standalone on Apple Watch",
            "Add cards in seconds",
            "No account",
            "No analytics",
            "No ads",
            "No subscription"
        ]
        feature_group = VGroup()
        for i, text in enumerate(features):
            f_text = Text(f"• {text}", font=MONO, color=TEXT_COLOR, font_size=24)
            f_text.shift(UP * (2 - i*0.6))
            feature_group.add(f_text)
        
        feature_group.center()

        self.play(LaggedStart(*[FadeIn(f, shift=RIGHT*0.2) for f in feature_group], lag_ratio=0.2), run_time=2)
        self.wait(1)

        self.play(FadeOut(feature_group), run_time=0.8)

        # --- FINAL FRAME (23-25s) ---
        logo = Text("EEAccess", font=MONO, weight=BOLD, color=PRIMARY_BLUE, font_size=48)
        subline = Text("Your cards. Your wrist. Your freedom.", font=MONO, color=TEXT_COLOR, font_size=20)
        subline.next_to(logo, DOWN, buff=0.3)
        final_group = VGroup(logo, subline).center()

        self.play(FadeIn(watch), run_time=0.8)
        self.play(Write(final_group), run_time=1)
        self.wait(2)
