# Copyright © 2017-2023
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

unit package Whateverable::Uniprops;

our @prop-table is export =
‘Numeric properties’ => (
    (‘cjkAccountingNumeric’ ; ‘kAccountingNumeric’),
    (‘cjkOtherNumeric’ ; ‘kOtherNumeric’),
    (‘cjkPrimaryNumeric’ ; ‘kPrimaryNumeric’),
    (‘nv’ ; ‘Numeric_Value’),
),

‘String properties’ => (
    (‘cf’ ; ‘Case_Folding’),
    (‘cjkCompatibilityVariant’ ; ‘kCompatibilityVariant’),
    (‘dm’ ; ‘Decomposition_Mapping’),
    (‘FC_NFKC’ ; ‘FC_NFKC_Closure’),
    (‘lc’ ; ‘Lowercase_Mapping’),
    (‘NFKC_CF’ ; ‘NFKC_Casefold’),
    (‘scf’ ; ‘Simple_Case_Folding’ ; ‘sfc’),
    (‘slc’ ; ‘Simple_Lowercase_Mapping’),
    (‘stc’ ; ‘Simple_Titlecase_Mapping’),
    (‘suc’ ; ‘Simple_Uppercase_Mapping’),
    (‘tc’ ; ‘Titlecase_Mapping’),
    (‘uc’ ; ‘Uppercase_Mapping’),
),


‘Miscellaneous properties’ => (
    (‘bmg’ ; ‘Bidi_Mirroring_Glyph’),
    (‘bpb’ ; ‘Bidi_Paired_Bracket’),
    (‘cjkIICore’ ; ‘kIICore’),
    (‘cjkIRG_GSource’ ; ‘kIRG_GSource’),
    (‘cjkIRG_HSource’ ; ‘kIRG_HSource’),
    (‘cjkIRG_JSource’ ; ‘kIRG_JSource’),
    (‘cjkIRG_KPSource’ ; ‘kIRG_KPSource’),
    (‘cjkIRG_KSource’ ; ‘kIRG_KSource’),
    (‘cjkIRG_MSource’ ; ‘kIRG_MSource’),
    (‘cjkIRG_TSource’ ; ‘kIRG_TSource’),
    (‘cjkIRG_USource’ ; ‘kIRG_USource’),
    (‘cjkIRG_VSource’ ; ‘kIRG_VSource’),
    (‘cjkRSUnicode’ ; ‘kRSUnicode’ ; ‘Unicode_Radical_Stroke’; ‘URS’),
    (‘isc’ ; ‘ISO_Comment’),
    (‘JSN’ ; ‘Jamo_Short_Name’),
    (‘na’ ; ‘Name’),
    (‘na1’ ; ‘Unicode_1_Name’),
    (‘Name_Alias’ ; ‘Name_Alias’),
    (‘scx’ ; ‘Script_Extensions’),
),

‘Catalog properties’ => (
    (‘age’ ; ‘Age’),
    (‘blk’ ; ‘Block’),
    (‘sc’ ; ‘Script’),
),

‘Enumerated properties’ => (
    (‘bc’ ; ‘Bidi_Class’),
    (‘bpt’ ; ‘Bidi_Paired_Bracket_Type’),
    (‘ccc’ ; ‘Canonical_Combining_Class’),
    (‘dt’ ; ‘Decomposition_Type’),
    (‘ea’ ; ‘East_Asian_Width’),
    (‘gc’ ; ‘General_Category’),
    (‘GCB’ ; ‘Grapheme_Cluster_Break’),
    (‘hst’ ; ‘Hangul_Syllable_Type’),
    (‘InPC’ ; ‘Indic_Positional_Category’),
    (‘InSC’ ; ‘Indic_Syllabic_Category’),
    (‘jg’ ; ‘Joining_Group’),
    (‘jt’ ; ‘Joining_Type’),
    (‘lb’ ; ‘Line_Break’),
    (‘NFC_QC’ ; ‘NFC_Quick_Check’),
    (‘NFD_QC’ ; ‘NFD_Quick_Check’),
    (‘NFKC_QC’ ; ‘NFKC_Quick_Check’),
    (‘NFKD_QC’ ; ‘NFKD_Quick_Check’),
    (‘nt’ ; ‘Numeric_Type’),
    (‘SB’ ; ‘Sentence_Break’),
    (‘WB’ ; ‘Word_Break’),
),

‘Binary Properties’ => (
    (‘AHex’ ; ‘ASCII_Hex_Digit’),
    (‘Alpha’ ; ‘Alphabetic’),
    (‘Bidi_C’ ; ‘Bidi_Control’),
    (‘Bidi_M’ ; ‘Bidi_Mirrored’),
    (‘Cased’ ; ‘Cased’),
    (‘CE’ ; ‘Composition_Exclusion’),
    (‘CI’ ; ‘Case_Ignorable’),
    (‘Comp_Ex’ ; ‘Full_Composition_Exclusion’),
    (‘CWCF’ ; ‘Changes_When_Casefolded’),
    (‘CWCM’ ; ‘Changes_When_Casemapped’),
    (‘CWKCF’ ; ‘Changes_When_NFKC_Casefolded’),
    (‘CWL’ ; ‘Changes_When_Lowercased’),
    (‘CWT’ ; ‘Changes_When_Titlecased’),
    (‘CWU’ ; ‘Changes_When_Uppercased’),
    (‘Dash’ ; ‘Dash’),
    (‘Dep’ ; ‘Deprecated’),
    (‘DI’ ; ‘Default_Ignorable_Code_Point’),
    (‘Dia’ ; ‘Diacritic’),
    (‘Ext’ ; ‘Extender’),
    (‘Gr_Base’ ; ‘Grapheme_Base’),
    (‘Gr_Ext’ ; ‘Grapheme_Extend’),
    (‘Gr_Link’ ; ‘Grapheme_Link’),
    (‘Hex’ ; ‘Hex_Digit’),
    (‘Hyphen’ ; ‘Hyphen’),
    (‘IDC’ ; ‘ID_Continue’),
    (‘Ideo’ ; ‘Ideographic’),
    (‘IDS’ ; ‘ID_Start’),
    (‘IDSB’ ; ‘IDS_Binary_Operator’),
    (‘IDST’ ; ‘IDS_Trinary_Operator’),
    (‘Join_C’ ; ‘Join_Control’),
    (‘LOE’ ; ‘Logical_Order_Exception’),
    (‘Lower’ ; ‘Lowercase’),
    (‘Math’ ; ‘Math’),
    (‘NChar’ ; ‘Noncharacter_Code_Point’),
    (‘OAlpha’ ; ‘Other_Alphabetic’),
    (‘ODI’ ; ‘Other_Default_Ignorable_Code_Point’),
    (‘OGr_Ext’ ; ‘Other_Grapheme_Extend’),
    (‘OIDC’ ; ‘Other_ID_Continue’),
    (‘OIDS’ ; ‘Other_ID_Start’),
    (‘OLower’ ; ‘Other_Lowercase’),
    (‘OMath’ ; ‘Other_Math’),
    (‘OUpper’ ; ‘Other_Uppercase’),
    (‘Pat_Syn’ ; ‘Pattern_Syntax’),
    (‘Pat_WS’ ; ‘Pattern_White_Space’),
    (‘PCM’ ; ‘Prepended_Concatenation_Mark’),
    (‘QMark’ ; ‘Quotation_Mark’),
    (‘Radical’ ; ‘Radical’),
    (‘SD’ ; ‘Soft_Dotted’),
    (‘STerm’ ; ‘Sentence_Terminal’),
    (‘Term’ ; ‘Terminal_Punctuation’),
    (‘UIdeo’ ; ‘Unified_Ideograph’),
    (‘Upper’ ; ‘Uppercase’),
    (‘VS’ ; ‘Variation_Selector’),
    (‘WSpace’ ; ‘White_Space ; space’),
    (‘XIDC’ ; ‘XID_Continue’),
    (‘XIDS’ ; ‘XID_Start’),
    (‘XO_NFC’ ; ‘Expands_On_NFC’),
    (‘XO_NFD’ ; ‘Expands_On_NFD’),
    (‘XO_NFKC’ ; ‘Expands_On_NFKC’),
    (‘XO_NFKD’ ; ‘Expands_On_NFKD’),
),

‘Emoji’ => (
    (‘Emoji’),
    (‘Emoji_Presentation’),
    (‘Emoji_Modifier’),
    (‘Emoji_Modifier_Base’),
    (‘Emoji_All’),
    (‘Emoji_Zwj_Sequences’),
),

‘Implementation specific properties’ => (
    (‘Numeric_Value_Numerator’),
    (‘Numeric_Value_Denominator’),
    (‘NFG_QC’),
    (‘MVM_COLLATION_PRIMARY’),
    (‘MVM_COLLATION_SECONDARY’),
    (‘MVM_COLLATION_TERTIARY’),
    (‘MVM_COLLATION_QC’),
),

# vim: expandtab shiftwidth=4 ft=perl6
