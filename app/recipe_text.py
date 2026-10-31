"""Render Cookidoo's private-use cooking symbols as understandable text."""
import html
import re


def readable_step(text):
    for _ in range(2):
        decoded = html.unescape(text)
        if decoded == text:
            break
        text = decoded
    # These mode icons accompany the same written mode name in Cookidoo's text.
    text = re.sub(r'Anbraten\s*\ue026', 'Anbraten', text, flags=re.IGNORECASE)
    text = re.sub(r'Pürieren\s*\ue01e', 'Pürieren', text, flags=re.IGNORECASE)
    text = re.sub(r'\ue937\s*Offenes Kochen', 'Offenes Kochen', text, flags=re.IGNORECASE)
    text = re.sub(r'\ue904\s*(?=\d)', '', text)
    text = re.sub(r'Stufe\s*\ue002', 'Sanftrührstufe', text, flags=re.IGNORECASE)
    for char, replacement in {'\ue003':'Linkslauf', '\ue002':'Sanftrührstufe', '\ue026':'Anbraten', '\ue01e':'Pürieren', '\ue937':'Offenes Kochen', '\ue904':'Temperatur'}.items():
        text = text.replace(char, replacement)
    return re.sub(r'[\ue000-\uf8ff]', '[Thermomix-Symbol]', text)


def readable_instructions(value):
    if isinstance(value, str):
        return readable_step(value)
    if isinstance(value, list):
        return [readable_instructions(item) for item in value]
    if isinstance(value, dict):
        return {key: readable_instructions(item) for key, item in value.items()}
    return value
